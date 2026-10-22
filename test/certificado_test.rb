require_relative "test_helper"
require "tempfile"
require "open3"
require "json"

class NfseNacionalCertificadoTest < NfseNacional::TestCase
  test "carrega PKCS12 com chave correspondente CNPJ e validade" do
    expiry = Time.utc(2030, 1, 1)
    cert = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx(not_after: expiry), senha: "teste")
    assert_instance_of OpenSSL::X509::Certificate, cert.certificate
    assert_instance_of OpenSSL::PKey::RSA, cert.key
    assert cert.certificate.check_private_key(cert.key)
    assert_equal "12345678000195", cert.cnpj
    assert_equal expiry, cert.valid_until
    assert_not cert.expired?(expiry - 1)
    assert cert.expired?(expiry)
    assert cert.expired?(expiry + 1)
    travel_to(expiry) { assert cert.expired? }
  end

  test "lê CNPJ alfanumérico do subject" do
    cert = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx(cnpj: "12ABC34501DE35"), senha: "teste")
    assert_equal "12ABC34501DE35", cert.cnpj
  end

  test "subject sem CNPJ retorna nil" do
    [nil, "12345678909", "123456780001950", "12abc34501de35", "12ABC34501DEAB"].each do |cnpj|
      cert = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx(cnpj: cnpj), senha: "teste")
      assert_nil cert.cnpj
    end
  end

  test "carrega PFX legado com RC2 buscando o provider do sistema" do
    result = load_in_subprocess(legacy_pfx)

    assert_nil result["error"]
    assert_equal "12345678000195", result["cnpj"]
    assert result["key_matches"]
    assert_includes result["providers"], "legacy"
  end

  test "respeita OPENSSL_MODULES definido ao carregar PFX legado" do
    modules_output, stderr, status = Open3.capture3("openssl", "info", "-modulesdir")
    assert status.success?, stderr
    modules = modules_output.strip
    result = load_in_subprocess(legacy_pfx, modules: modules)

    assert_nil result["error"]
    assert_equal modules, result["modules"]
  end

  test "senha incorreta no legado continua sendo erro de senha" do
    result = load_in_subprocess(legacy_pfx, password: "incorreta")

    assert_equal "Não foi possível abrir o certificado A1: arquivo inválido ou senha incorreta", result["error"]
  end

  test "provider indisponível informa formato antigo em vez de senha incorreta" do
    result = load_in_subprocess(legacy_pfx, provider_unavailable: true)

    assert_equal "Certificado em formato antigo (RC2/3DES) que este servidor não consegue abrir. Reexporte o .pfx com criptografia AES ou fale com o suporte.", result["error"]
  end

  test "OPENSSL_MODULES inválido não é substituído pelo caminho do sistema" do
    result = load_in_subprocess(legacy_pfx, modules: "/diretorio-inexistente-nfse")

    assert_equal "/diretorio-inexistente-nfse", result["modules"]
    assert_match(/formato antigo/, result["error"])
  end

  test "recusa certificado e chave que não combinam" do
    original = OpenSSL::PKCS12.new(NfseTestCertificate.pfx, "teste")
    mismatched = Struct.new(:certificate, :key).new(original.certificate, OpenSSL::PKey::RSA.new(2048))

    OpenSSL::PKCS12.stub(:new, mismatched) do
      error = assert_raises(NfseNacional::Certificado::Invalid) do
        NfseNacional::Certificado.new(pfx: "simulado", senha: "teste")
      end
      assert_equal "o certificado e a chave do arquivo não combinam", error.message
    end
  end

  test "senha incorreta e PKCS12 corrompido geram erro em português sem expor senha" do
    [[NfseTestCertificate.pfx, "segredo-incorreto"], ["corrompido", "segredo-incorreto"]].each do |pfx, password|
      error = assert_raises(NfseNacional::Certificado::Invalid) do
        NfseNacional::Certificado.new(pfx: pfx, senha: password)
      end
      assert_match(/certificado|senha/i, error.message)
      assert_not_includes error.message, password
    end
  end

  private

  def legacy_pfx
    original = OpenSSL::PKCS12.new(NfseTestCertificate.pfx, "teste")
    OpenSSL::PKCS12.create("teste", "Legado teste", original.key, original.certificate,
      nil, "PBE-SHA1-RC2-40", "PBE-SHA1-RC2-40").to_der
  rescue OpenSSL::OpenSSLError
    Tempfile.create(["nfse-cert", ".pem"]) do |cert_file|
      Tempfile.create(["nfse-key", ".pem"]) do |key_file|
        cert_file.write(original.certificate.to_pem)
        key_file.write(original.key.to_pem)
        cert_file.flush
        key_file.flush
        output, error, status = Open3.capture3("openssl", "pkcs12", "-export", "-legacy",
          "-keypbe", "PBE-SHA1-RC2-40", "-certpbe", "PBE-SHA1-RC2-40",
          "-in", cert_file.path, "-inkey", key_file.path, "-passout", "pass:teste", stdin_data: "")
        assert status.success?, "Não foi possível gerar PFX sintético legado: #{error}"
        output
      end
    end
  end

  # Providers são globais no OpenSSL: cada cenário começa sem legacy carregado.
  def load_in_subprocess(pfx, password: "teste", modules: nil, provider_unavailable: false)
    script = <<~RUBY
      require "json"
      require "minitest/mock"
      require "nfse_nacional/certificado"
      load_certificate = lambda do
        begin
          cert = NfseNacional::Certificado.new(pfx: STDIN.read, senha: ARGV.fetch(0))
          result = {cnpj: cert.cnpj, key_matches: cert.certificate.check_private_key(cert.key)}
        rescue NfseNacional::Certificado::Invalid => e
          result = {error: e.message}
        end
        puts JSON.generate(result.merge(modules: ENV["OPENSSL_MODULES"], providers: OpenSSL::Provider.provider_names))
      end
      if ARGV.fetch(1) == "true"
        OpenSSL::Provider.stub(:load, ->(*) { raise OpenSSL::Provider::ProviderError, "indisponível" }) do
          load_certificate.call
        end
      else
        load_certificate.call
      end
    RUBY
    output, error, status = Open3.capture3({"OPENSSL_MODULES" => modules}, RbConfig.ruby,
      "-I#{File.expand_path("../lib", __dir__)}", "-e", script, password, provider_unavailable.to_s, stdin_data: pfx)
    assert status.success?, error
    JSON.parse(output)
  end
end
