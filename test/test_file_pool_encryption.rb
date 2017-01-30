require 'rubygems'
require 'shoulda'
require 'file_pool'

class FilePoolTest < Test::Unit::TestCase

  def setup
    @test_dir = "#{File.dirname(__FILE__)}/files"
    @pool_root = "#{File.dirname(__FILE__)}/fp_root"
    @file_pool_config = "#{File.dirname(__FILE__)}/file_pool_cfg.yml"
    FileUtils.touch @file_pool_config
    FilePool.setup @pool_root, @file_pool_config
  end

  def teardown
    FileUtils.rm_r(Dir.glob @pool_root+"/*")
    FileUtils.rm_r(Dir.glob "#{@pool_root}_secured/*")
    FileUtils.rm_r(Dir.glob @file_pool_config)
  end

  context "File Pool" do
    should "store encrypted files" do
      fid = FilePool.add(@test_dir+"/a")

      assert UUIDTools::UUID.parse(fid).valid?

      md5_orig = Digest::MD5.hexdigest(File.open(@test_dir+"/a").read)
      md5_pooled = Digest::MD5.hexdigest(File.open(FilePool.path(fid)).read)

      assert_equal md5_orig, md5_pooled
    end

    should "return path from stored encrypted files is in the tmp folder" do

      fida = FilePool.add(@test_dir+"/a")
      assert UUIDTools::UUID.parse(fida).valid?

      fidb = FilePool.add(@test_dir+"/b")
      assert UUIDTools::UUID.parse(fidb).valid?

      fidc = FilePool.add(@test_dir+"/c")
      assert UUIDTools::UUID.parse(fidc).valid?

      fidd = FilePool.add!(@test_dir+"/d")
      assert UUIDTools::UUID.parse(fidd).valid?

      assert_equal Digest::MD5.hexdigest(File.open(@test_dir+"/a").read),
                     Digest::MD5.hexdigest(File.open(FilePool.path(fida)).read)
      assert_equal Digest::MD5.hexdigest(File.open(@test_dir+"/b").read),
                     Digest::MD5.hexdigest(File.open(FilePool.path(fidb)).read)
      assert_equal Digest::MD5.hexdigest(File.open(@test_dir+"/c").read),
                     Digest::MD5.hexdigest(File.open(FilePool.path(fidc)).read)
      assert_equal Digest::MD5.hexdigest(File.open(@test_dir+"/d").read),
                     Digest::MD5.hexdigest(File.open(FilePool.path(fidd)).read)
      assert_equal 'tmp', FilePool.path(fida).split('/')[1]
      assert_equal 'tmp', FilePool.path(fidb).split('/')[1]
      assert_equal 'tmp', FilePool.path(fidc).split('/')[1]
      assert_equal 'tmp', FilePool.path(fidd).split('/')[1]
    end

    should "remove files from encrypted pool" do

      fidb = FilePool.add(@test_dir+"/b")
      fidc = FilePool.add!(@test_dir+"/c")
      fidd = FilePool.add!(@test_dir+"/d")

      path_c = FilePool.path_raw(fidc)
      FilePool.remove(fidc)

      assert !File.exist?(path_c)
      assert File.exist?(FilePool.path_raw(fidb))
      assert File.exist?(FilePool.path_raw(fidd))

    end

    should "throw exceptions when using add! and remove! on failure in encrypted mode" do
      assert_raises(FilePool::InvalidFileId) do
        FilePool.remove!("invalid-id")
      end

      assert_raises(Errno::ENOENT) do
        FilePool.remove!("61e9b2d1-1738-440d-9b3d-e3c64876f2b0")
      end

      assert_raises(Errno::ENOENT) do
        FilePool.add!("/not/here/foo.png")
      end

    end

    should "not throw exceptions when using add and remove on failure in encrypted mode" do
      assert !FilePool.remove("invalid-id")
      assert !FilePool.remove("61e9b2d1-1738-440d-9b3d-e3c64876f2b0")
      assert !FilePool.add("/not/here/foo.png")
    end
  end
end
