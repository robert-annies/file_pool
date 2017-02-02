# -*- coding: utf-8 -*-
require 'file_pool/version'
require 'uuidtools'
require 'tempfile'
require 'openssl'
require 'yaml'

module FilePool

  class InvalidFileId < Exception; end

  #
  # Setup the root directory of the file pool and configure encryption
  #
  # === Parameters:
  #
  # root (String)::
  #   absolute path of the file pool's root directory under which all files will be stored.
  # config_file_path (String)::
  #   path to the config file of the filepool.
  # options (Hash)::
  #   * :secrets_file (String)
  #     path to file containing key and IV for encryption (if omitted FilePool
  #     does not encrypt/decrypt). If file is not present, the file is initialized with a
  #     new random key and IV.
  #   * :encryption_block_size (Integer) sets the block size for
  #     encryption/decryption in bytes. Larger blocks need more memory and less time (less IO).
  #     Defaults to 1'048'576 (1 MiB).
  def self.setup root, options={}
    unless(unknown = options.keys - [:encryption_block_size, :secrets_file]).empty?
      puts "FilePool Warning: unknown option(s) passed to #setup: #{unknown.inspect}"
    end
    @@root = root
    @@crypted_mode = false
    @@block_size = options[:encryption_block_size] || (1024*1024)
    configure options[:secrets_file]
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

    if @@crypted_mode
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
  # Return the file's path corresponding to the passed file ID, no matter if it
  # exists or not. In encrypting mode the file is first decrypted and the
  # returned path will point to a temporary location of the decrypted file.
  #
  # To get the path of the encrypted file pass :decrypt => false, as an option.
  #
  # === Parameters:
  #
  # fid (String)::
  #   File ID which was generated by a previous #add operation.
  #
  # options (Hash)::
  #   :decrypt (true,false) In encryption mode don't decrypt, but return the encrypted file's path. Defaults to +true+.
  #
  # === Return Value:
  #
  # :: *String*, absolute path of the file in the pool or to temporary location if it was decrypted.
  def self.path fid, options={}
    options[:decrypt] = true unless options[:decrypt] == false

    raise InvalidFileId unless valid?(fid)

    # file present in pool?
    if File.file?(id2dir_secured(fid) + "/#{fid}")
      # present in secured tree
      if @@crypted_mode
        if options[:decrypt]
          # return path of decrypted file (tmp path)
          decrypt id2dir_secured(fid) + "/#{fid}"
        else
          id2dir_secured(fid) + "/#{fid}"
        end
      else
        id2dir_secured(fid) + "/#{fid}"
      end
    elsif File.file?(id2dir(fid) + "/#{fid}")
      # present in plain tree
      id2dir(fid) + "/#{fid}"
    else
      # not present
      if @@crypted_mode
        id2dir_secured(fid) + "/#{fid}"
      else
        id2dir(fid) + "/#{fid}"
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
    FileUtils.rm path(fid, :decrypt => false)
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
    result = Tempfile.new 'FilePool-encrypt'

    buf = ''

    File.open(path) do |inf|
      while inf.read(@@block_size, buf)
        result << cipher.update(buf)
      end
      result << cipher.final
    end

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
    output = Tempfile.new 'FilePool-decrypt'

    buf = ''
    File.open(path) do |inf|
      while inf.read(@@block_size, buf)
        output << decipher.update(buf)
      end
      output << decipher.final
    end

    output.open # re-open for reading, prevents early deletion of tempfile
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
    cipher.iv  = @@iv
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
    decipher.iv  = @@iv
    decipher
  end

  #
  # Retrieves configuration from config file or creates
  # a new one in case there's none available.
  #
  def self.configure config_file
    unless config_file.nil?
      @@crypted_mode = true
      begin
        config = YAML.load_file(config_file)
        @@iv  = config[:iv]
        @@key = config[:key]
      rescue Errno::ENOENT
        cipher = OpenSSL::Cipher::AES.new(256, :CBC)
        @@iv  = cipher.random_iv
        @@key = cipher.random_key
        cipher.key = @@key
        cfg = File.open(config_file, 'w')
        cfg.write({:iv => @@iv, :key => @@key}.to_yaml)
        cfg.close
        File.chmod(0400, config_file)
      rescue => other_error
        raise "FilePool: Could not load secrets from #{config_file}: #{other_error}"
      end
    end
  end

  #
  # Tell wehther a file was stored with encryption. (checks for presence in
  # the secured part of the file pool. If the file was actually encrypted cannot
  # be answered)
  #
  def self.encrypted? fid
    File.file?(id2dir_secured(fid) + "/#{fid}")
  end
end
