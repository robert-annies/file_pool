require 'rubygems'
require 'shoulda'
require 'file_pool'

class FilePoolTest < Test::Unit::TestCase

  def setup
    @test_dir = "#{File.dirname(__FILE__)}/files"
    @pool_root = "#{File.dirname(__FILE__)}/fp_root"
    FilePool.setup @pool_root
  end

  def teardown
    FileUtils.rm_r(Dir.glob @pool_root+"/*")
  end

  context "File Pool" do
    should "store files" do
      fid = FilePool.add(@test_dir+"/a")

      assert UUIDTools::UUID.parse(fid).valid?

      md5_orig = Digest::MD5.hexdigest(File.open(@test_dir+"/a").read)
      md5_pooled = Digest::MD5.hexdigest(File.open(@pool_root + "/#{fid[0,1]}/#{fid[1,1]}/#{fid[2,1]}/#{fid}").read)

      assert_equal md5_orig, md5_pooled
    end

    should "return path from stored files" do

      fidb = FilePool.add(@test_dir+"/b")
      fidc = FilePool.add(@test_dir+"/c")
      fidd = FilePool.add!(@test_dir+"/d")

      assert_equal "#{@pool_root}/#{fidb[0,1]}/#{fidb[1,1]}/#{fidb[2,1]}/#{fidb}", FilePool.path(fidb)
      assert_equal "#{@pool_root}/#{fidc[0,1]}/#{fidc[1,1]}/#{fidc[2,1]}/#{fidc}", FilePool.path(fidc)
      assert_equal "#{@pool_root}/#{fidd[0,1]}/#{fidd[1,1]}/#{fidd[2,1]}/#{fidd}", FilePool.path(fidd)

    end

    should "remove files from pool" do

      fidb = FilePool.add(@test_dir+"/b")
      fidc = FilePool.add!(@test_dir+"/c")
      fidd = FilePool.add!(@test_dir+"/d")

      path_c = FilePool.path(fidc)
      FilePool.remove(fidc)

      assert !File.exist?(path_c)
      assert File.exist?(FilePool.path(fidb))
      assert File.exist?(FilePool.path(fidd))

    end

    should "throw excceptions when using add! and remove! on failure" do
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

    should "not throw exceptions when using add and remove on failure" do
      assert !FilePool.remove("invalid-id")
      assert !FilePool.remove("61e9b2d1-1738-440d-9b3d-e3c64876f2b0")
      assert !FilePool.add("/not/here/foo.png")
    end
  end
end
