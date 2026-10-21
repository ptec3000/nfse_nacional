require_relative "test_helper"

class NfseNacionalTestCaseTest < NfseNacional::TestCase
  test "travel_to para o relógio e travel avança" do
    parado = Time.new(2026, 10, 16, 12, 30, 0, "-03:00")
    travel_to(parado) do
      assert_equal parado, Time.now
      travel 60
      assert_equal parado + 60, Time.now
    end
    assert_not_equal parado + 60, Time.now
  end

  test "aliases do ActiveSupport" do
    assert_not false
    assert_not_empty [1]
    assert_not_includes [1], 2
  end
end
