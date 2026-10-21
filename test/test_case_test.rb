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

  [false, true].each do |custom_teardown|
    test "travel fora de travel_to não vaza com teardown próprio #{custom_teardown}" do
      clock_test = Class.new(NfseNacional::TestCase) do
        define_method(:advance_clock) { travel 3600 }
        teardown { @teardown_called = true } if custom_teardown
        attr_reader :teardown_called
      end.new("advance_clock")

      result = clock_test.run

      assert result.passed?, result.failures.inspect
      assert clock_test.teardown_called if custom_teardown
      assert_nil Thread.current[:nfse_nacional_now]
    ensure
      Thread.current[:nfse_nacional_now] = nil
    end
  end
end
