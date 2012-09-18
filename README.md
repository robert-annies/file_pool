# FilePool

FilePool helps to manage a large number of files in a Ruby project. It
takes care of the storage of files in a balanced directory tree and
generates unique identifiers for all files. It also comes in handy
when dealing with only a few files.

FilePool does not deal with file meta information. It's only purpose
is to return a file's location given a file identifier, which was
generated when the file was added to the pool.

The identifiers are strings of UUID Type 4 (random), which are also
used as file names. The directory tree is a 3 level structure using
the 3 first hexadecimal digits of a UUID as path. For example:

    0/d/6/0d6f8dd9-8deb-4500-bb85-2d0796241963
    0/c/f/0cfb082a-fd57-490c-978b-e47d5948bc8b
    6/1/d/61ddfe33-13f3-4f71-9234-5fbbf5c4fc2c

FilePool is tested with Ruby 1.8.7 and 1.9.3.

## Installation

Add this line to your application's Gemfile:

    gem 'file_pool'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install file_pool

## Usage

### Setup

Set up the root path under which all files will reside:

    FilePool.setup '/var/lib/files'

In a Rails project the file pool setup would be placed in an intializer:

    config/initializers/file_pool.rb

### Example Usage

Adding files (perhaps after completed upload)

    fid = FilePool.add('/Temp/p348dvhn4')

Get location of previously added file

    path = FilePool.path(fid)

Remove a file

    FilePool.remove(fid)

### Maintenance

FilePool has a straight forward way of storing files. It doesn't use
any form of index. As long as you stick to directory structure
outlined above you can:

* move the entire pool somewhere else
* split the pool using symbolic links or mount points to remote file systems
* merge file pools by copying them into one

There is no risk of overwriting, because UUID type 4 file names are
unique. (up to an extremely small collision probability).

### Notes

Make sure to store the generated file identifiers safely. There is no
way of identifying a file again when it's ID is lost. In doubt generate a hash
value from the file and store it somewhere else.

For large files the pool root should be on the same file system as the files
added to the pool. Then adding a file returns immediately. Otherwise
files will be copied which may take a significant time.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
