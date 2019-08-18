require_relative "test_helper"

class PhotoRepoTest < Minitest::Test
  def test_loadable
    repo = PhotoRepo.new "#{__dir__}/test_repos/noah_only"
    assert_equal ["noah"], repo.filter["required"]
    assert_equal [], repo.filter["disallowed"]
  end
end
