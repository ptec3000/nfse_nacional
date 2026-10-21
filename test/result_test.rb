require_relative "test_helper"

class NfseNacionalResultTest < NfseNacional::TestCase
  test "o app consegue montar um Result de erro retentável" do
    result = NfseNacional::Result.new(status: :error, errors: ["Falha"], request_xml: "<x/>", body: "corpo")
    assert result.retryable?
    assert_equal ["Falha"], result.errors
  end

  test "rejeição não é retentável" do
    refute NfseNacional::Result.new(status: :rejected, errors: ["E0001"]).retryable?
  end
end
