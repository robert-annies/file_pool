# -*- coding: utf-8 -*-
require 'file_pool/version'
require 'uuidtools'
require 'tempfile'
require 'openssl'
require 'base64'
=begin
<em>Robert Anniés (2012)</em>

== Introduction

FilePool helps to manage a large number of files in a Ruby project. It
takes care of the storage of files in a balanced directory tree and
generates unique identifiers for all files. It also comes in handy
when delaing with only a few files.

FilePool does not deal with file meta information. It's only purpose
is to return a file's location given a file identifier, which was
generated when the file was added to the pool.

The identifiers are strings of UUID Type 4 (random), which are also
used as file names. The directory tree is a 3 level structure using
the 3 first hexadecimal digits of a UUID as path. For example:

  0/d/6/0d6f8dd9-8deb-4500-bb85-2d0796241963
  0/c/f/0cfb082a-fd57-490c-978b-e47d5948bc8b
  6/1/d/61ddfe33-13f3-4f71-9234-5fbbf5c4fc2c

== Examples

=== Setup
The root path must be specified:

  FilePool.setup '/var/lib/files'

In a Rails project the file pool setup should be placed in an intializer:

  config/initializers/file_pool.rb

=== Usage

Adding files (perhaps after completed upload)

  fid = FilePool.add('/Temp/p348dvhn4')

Get location of previously added file

  path = FilePool.path(fid)

Remove a file

  FilePool.remove(fid)

== Maintenance

FilePool has a straight forward way of storing files. It doesn't use
any form of index. As long as you stick to directory structure
outlined above you can:

* move the entire pool somewhere else
* split the pool using symbolic links or mount points to remote file systems
* merge file pools by copying them into one

There is no risk of overwriting, because UUID type 4 file names are
unique. (up to an extremely small collision probability).

== Notes

Make sure to store the generated file identifiers safely. There is no
way of identifying a file again when it's ID is lost. In doubt generate a hash
value from the file and store it somewhere else.

For large files the pool root should be on the same file system as the files
added to the pool. Then adding a file returns immediately. Otherwise
files will be copied which may take a significant time.

=end
module FilePool

  class InvalidFileId < Exception; end

  #
  # Setup the root directory of the file pool root.
  #
  # === Parameters:
  #
  # root (String)::
  #   absolute path of the file pool's root directory under which all files will be stored.
  # secret (String)::
  #   secret key to crypt and decrypt the contents of the filepool.
  def self.setup root, secret = nil
    @@root = root
    @@secret = secret
    unless @@secret.nil?
      cipher = OpenSSL::Cipher::AES.new(256, :CBC)
      cipher.encrypt
      @@iv  = cipher.random_iv
      @@salt  =  OpenSSL::Random.random_bytes 16
      @@iter  = 20000
      @@key_len = cipher.key_len
      @@digest = OpenSSL::Digest::SHA256.new
      @@key = OpenSSL::PKCS5.pbkdf2_hmac(@@secret, @@salt, @@iter, cipher.key_len, @@digest)
      cipher.key = @@key
    end
  end

  #
  # Add a file to the file pool.
  #
  # Creates hard-links (ln) when file at +path+ is on same file system as
  # pool, otherwise copies it. When dealing with large files the
  # latter should be avoided, because it takes more time and space.
  #
  # Throws standard file exceptions when unable to store the file. See
  # also FilePool.add to avoid it.
  #
  # === Parameters:
  #
  # path (String)::
  #   path of the file to add.
  #
  # === Return Value:
  #
  # :: *String* containing a new unique ID for the file added.
  def self.add! path
    newid = uuid
    target = path newid

    unless @@secret.nil?
      FileUtils.mkpath(id2dir_secured newid)
      path = crypt(path)
    else
      FileUtils.mkpath(id2dir newid)
    end
    FileUtils.link(path, target)

    return newid

  rescue Errno::EXDEV
    FileUtils.copy(path, target)
    return newid
  end

  #
  # Add a file to the file pool.
  #
  # Same as FilePool.add!, but doesn't throw exceptions.
  #
  # === Parameters:
  #
  # source (String)::
  #   path of the file to add.
  #
  # === Return Value:
  #
  # :: *String* containing a new unique ID for the file added.
  # :: +false+ when the file could not be stored.
  def self.add path
    self.add!(path)

  rescue Exception => ex
    return false
  end

  #
  # Return the path where a previously added file is available by its ID.
  #
  # === Parameters:
  #
  # fid (String)::
  #   File ID which was generated by a previous #add operation.
  #
  # === Return Value:
  #
  # :: *String*, absolute path of the file in the pool.
  def self.path fid
    raise InvalidFileId unless valid?(fid)
    # Is it crypted or not?
    if File.file?(id2dir_secured(fid) + "/#{fid}")
      decrypt id2dir_secured(fid) + "/#{fid}"
    else
      if @@secret.nil?
        id2dir(fid) + "/#{fid}"
      else
        id2dir_secured(fid) + "/#{fid}"
      end
    end
  end

  #
  # Return the real path of a previously added file by its ID.
  #
  # === Parameters:
  #
  # fid (String)::
  #   File ID which was generated by a previous #add operation.
  #
  # === Return Value:
  #
  # :: *String*, absolute path of the file in the pool.
  def self.path_raw fid
    raise InvalidFileId unless valid?(fid)
    # Is it crypted or not?
    if File.file?(id2dir_secured(fid) + "/#{fid}")
      id2dir_secured(fid) + "/#{fid}"
    else
      if @@secret.nil?
        id2dir(fid) + "/#{fid}"
      else
        id2dir_secured(fid) + "/#{fid}"
      end
    end
  end

  #
  # Remove a previously added file by its ID. Same as FilePool.remove,
  # but throws exceptions on failure.
  #
  # === Parameters:
  #
  # fid (String)::
  #   File ID which was generated by a previous #add operation.
  def self.remove! fid
    FileUtils.rm path_raw(fid)
  end

  #
  # Remove a previously added file by its ID. Same as FilePool.remove!, but
  # doesn't throw exceptions.
  #
  # === Parameters:
  #
  # fid (String)::
  #   File ID which was generated by a previous #add operation.
  #
  # === Return Value:
  #
  # :: *Boolean*, +true+ if file was removed successfully, +false+ else
  def self.remove fid
    self.remove! fid
  rescue Exception => ex
    return false
  end

  #
  # Returns some statistics about the current pool. (It may be slow if
  # the pool contains very many files as it computes them from scratch.)
  #
  # === Return Value
  #
  # :: *Hash* with keys
  #   :total_number (Integer)::
  #     Number of files in pool
  #   :total_size (Integer)::
  #     Total number of bytes of all files
  #   :median_size (Float)::
  #     Median of file sizes (most frequent size)
  #   :last_add (Time)::
  #     Time and Date of last add operation

  def self.stat
    all_files = Dir.glob("#{root}_secured/*/*/*/*")
    all_files << Dir.glob("#{root}/*/*/*/*")
    all_stats = all_files.map{|f| File.stat(f) }

    {
      :total_size => all_stats.inject(0){|sum,stat| sum+=stat.size},
      :median_size => median(all_stats.map{|stat| stat.size}),
      :file_number => all_files.length,
      :last_add => all_stats.map{|stat| stat.ctime}.max
    }
  end


  private

  def self.root
    @@root rescue raise("FilePool: no root directory defined. Use FilePool#setup.")
  end

  # path from fid without file name
  def self.id2dir fid
    "#{root}/#{fid[0,1]}/#{fid[1,1]}/#{fid[2,1]}"
  end

  # secured path from fid without file name
  def self.id2dir_secured fid
    "#{root}_secured/#{fid[0,1]}/#{fid[1,1]}/#{fid[2,1]}"
  end

  # return a new UUID type 4 (random) as String
  def self.uuid
    UUIDTools::UUID.random_create.to_s
  end

  # return +true+ if _uuid_ is a valid UUID type 4
  def self.valid? uuid
    begin
      UUIDTools::UUID.parse(uuid).valid?
    rescue TypeError, ArgumentError
      return false
    end
  end

  # median file size
  def self.median(sizes)
    arr = sizes
    sortedarr = arr.sort
    medpt1 = arr.length / 2
    medpt2 = (arr.length+1)/2
    (sortedarr[medpt1] + sortedarr[medpt2]).to_f / 2
  end

  #
  # Crypt a file and store the result in the temp.
  #
  # Returns the path to the crypted file.
  #
  # === Parameters:
  #
  # path (String)::
  #   path of the file to crypt.
  #
  # === Return Value:
  #
  # :: *String*Path and name of the crypted file.
  def self.crypt path
    # Crypt the file in the temp folder and copy after
    cipher = create_cipher
    result = Tempfile.new uuid
    crypted_content = cipher.update(File.read(path))
    crypted_content << cipher.final
    result.write Base64.encode64(crypted_content)
    result.close
    result.path
  end

  #
  # Decrypt a file and give a path to it.
  #
  # Returns the path to the decrypted file.
  #
  # === Parameters:
  #
  # path (String)::
  #   path of the file to decrypt.
  #
  # === Return Value:
  #
  # :: *String*Path and name of the crypted file.
  def self.decrypt path
    decipher = create_decipher
    # Now decrypt the data:
    decrypted_content = decipher.update(Base64.decode64(File.read(path)))
    decrypted_content << decipher.final
    # Put it in a temp file
    output = Tempfile.new uuid
    output.write decrypted_content
    output.open
    output.path
  end

  #
  # Creates a cipher to encrypt data.
  #
  # Returns the cipher.
  #
  # === Return Value:
  #
  # :: *Openssl*Cipher object.
  def self.create_cipher
    cipher = OpenSSL::Cipher::AES.new(256, :CBC)
    cipher.encrypt
    cipher.key = @@key
    cipher
  end

  #
  # Creates a decipher to decrypt data.
  #
  # Returns the decipher.
  #
  # === Return Value:
  #
  # :: *Openssl*Cipher object
  def self.create_decipher
    decipher = OpenSSL::Cipher::AES.new(256, :CBC)
    decipher.decrypt
    decipher.key = @@key
    decipher
  end

end
