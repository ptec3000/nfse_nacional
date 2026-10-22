require_relative "test_helper"

class NfseNacionalSchemaTest < NfseNacional::TestCase
  def fixture(name) = File.read(fixture_path(name), encoding: "UTF-8")

  test "leiaute atual continua no XSD 1.00" do
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(fixture("dps_golden.xml")) }
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(fixture("dps_golden.xml"), leiaute: :atual) }
    assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_dps!(fixture("dps_rtc_homologacao.xml")) }
  end

  test "leiaute rtc aceita a ordem da homologação e recusa o XML atual" do
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(fixture("dps_rtc_homologacao.xml"), leiaute: :rtc) }
    error = assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_dps!(fixture("dps_golden.xml"), leiaute: :rtc) }
    assert_match(/finNFSe/, error.message)
  end

  test "leiaute rtc recusa gIBSCBS dentro de trib e finNFSe dentro de IBSCBS" do
    xml = fixture("dps_rtc_homologacao.xml")
    with_gibscbs = xml.sub("<trib><CST>000</CST><cClassTrib>000001</cClassTrib></trib>",
      "<trib><gIBSCBS><CST>000</CST><cClassTrib>000001</cClassTrib></gIBSCBS></trib>")
    assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_dps!(with_gibscbs, leiaute: :rtc) }
    fin_inside = xml.sub("<finNFSe>0</finNFSe>", "").sub("<IBSCBS>", "<IBSCBS><finNFSe>0</finNFSe>")
    assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_dps!(fin_inside, leiaute: :rtc) }
  end

  test "leiaute rtc segue o padrão oficial de série: até 89999" do
    xml = fixture("dps_rtc_homologacao.xml")
    assert_nothing_raised { NfseNacional::Schema.validate_dps!(xml.sub("<serie>900</serie>", "<serie>49999</serie>"), leiaute: :rtc) }
    assert_raises(NfseNacional::Schema::Invalid) { NfseNacional::Schema.validate_dps!(xml.sub("<serie>900</serie>", "<serie>99999</serie>"), leiaute: :rtc) }
  end

  test "leiaute desconhecido é erro de programação" do
    assert_raises(ArgumentError) { NfseNacional::Schema.validate_dps!(fixture("dps_golden.xml"), leiaute: :novo) }
  end
end
