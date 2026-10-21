require "time"
require_relative "test_helper"

# A Sefin recusa a DPS com dhEmi no futuro; o relógio do servidor pode estar adiantado
# em relação ao dela. Sem `now:`, o dhEmi sai alguns segundos antes do relógio real.
class NfseNacionalDhEmiSafetyMarginTest < NfseNacional::TestCase
  test "sem now explícito, dhEmi fica entre 4 e 10 segundos antes do relógio real" do
    started_at = Time.now
    xml = NfseNacional::Dps.new(
      ambiente: :homologacao,
      prestador: {cnpj: "12345678000195", municipio_ibge: "3106200", op_simp_nac: "3", reg_ap_trib_sn: "1", reg_esp_trib: "0"},
      tomador: {documento: "12345678909", nome: "Cliente Exemplo"},
      servico: {c_trib_nac: "010501", municipio_prestacao_ibge: "3106200", descricao: "Serviço de exemplo", nbs: "111032200"},
      valores: {valor: "10.00", trib_issqn: "1", tp_ret_issqn: "1", pis_cofins: nil},
      competencia: Date.new(2026, 4, 1), serie: "900", numero: "1"
    ).to_xml

    dhemi = Time.iso8601(xml[%r{<dhEmi>([^<]+)</dhEmi>}, 1])
    assert_operator dhemi, :<=, started_at - 4, "dhEmi sem margem de segurança: #{dhemi.iso8601}"
    assert_operator dhemi, :>=, started_at - 10, "dhEmi com margem excessiva: #{dhemi.iso8601}"
  end
end
