require_relative "test_helper"

class NfseNacionalNumeroTest < NfseNacional::TestCase
  test "fórmula legada de numeração" do
    expected = (Digest::SHA256.hexdigest("in_1PQRstuvWXyz").to_i(16) % 10**12).to_s
    assert_equal expected, NfseNacional::Numero.from_reference("in_1PQRstuvWXyz")
  end

  test "nunca zero" do
    Digest::SHA256.stub(:hexdigest, "0" * 64) do
      assert_equal "1", NfseNacional::Numero.from_reference("x")
    end
  end

  test "retorna uma string determinística com um a doze dígitos" do
    [nil, "", "in_1Abc", "referência"].each do |reference|
      number = NfseNacional::Numero.from_reference(reference)
      assert_match(/\A[1-9]\d{0,11}\z/, number)
      assert_equal number, NfseNacional::Numero.from_reference(reference)
    end
  end
end
