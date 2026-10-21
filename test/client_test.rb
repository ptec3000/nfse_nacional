require_relative "test_helper"
require "webmock/minitest"
require "zlib"
require "stringio"

class NfseNacionalClientTest < NfseNacional::TestCase
  BASE = "https://sefin.producaorestrita.nfse.gov.br/SefinNacional"
  KEY = "1" * 50

  setup do
    @certificate = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx, senha: "teste")
    @client = NfseNacional::Client.new(certificado: @certificate, ambiente: :homologacao)
    @xml = File.read(fixture_path("dps_golden.xml"))
    @dps = fake_dps(@xml)
  end

  test "revisão I1 lookup distingue rejeições e erros transitórios" do
    {403 => :rejected, 408 => :error, 429 => :error, 302 => :error}.each do |code, status|
      stub_request(:get, "#{BASE}/dps/DPS123").to_return(status: code)
      assert_equal status, @client.consultar_dps("DPS123").status
    end
  end

  test "revisão I1 POST 408 e 429 permitem retry" do
    [408, 429].each do |code|
      stub_request(:post, "#{BASE}/nfse").to_return(status: code)
      assert @client.emitir(@dps, idempotency_key: "digest").retryable?
    end
  end

  test "revisão I4 consulta XML completo pela chave" do
    request = stub_request(:get, "#{BASE}/nfse/#{KEY}").to_return(status: 200,
      body: JSON.generate(chaveAcesso: KEY, nfseXmlGZipB64: pack("<NFSe>recuperada</NFSe>")))
    result = @client.consultar_nfse(KEY)
    assert_equal :issued, result.status
    assert_equal "<NFSe>recuperada</NFSe>", result.nfse_xml
    assert_requested request
  end

  test "emite DPS validada antes da assinatura e recebe XML descompactado" do
    sent_xml = nil
    request = stub_request(:post, "#{BASE}/nfse").with(headers: {"Idempotency-Key" => "digest", "Content-Type" => "application/json"}) do |req|
      sent_xml = unpack(JSON.parse(req.body).fetch("dpsXmlGZipB64"))
      NfseNacional::Signer.verify!(sent_xml, node: "infDPS")
    end.to_return(status: 201, body: JSON.generate(chaveAcesso: KEY, nfseXmlGZipB64: pack("<NFSe>emitida</NFSe>")))
    result = @client.emitir(@dps, idempotency_key: "digest")
    assert_equal :issued, result.status
    assert_equal KEY, result.access_key
    assert_equal "<NFSe>emitida</NFSe>", result.nfse_xml
    assert_nil result.event_xml
    assert_equal 201, result.http_status
    assert_equal KEY, JSON.parse(result.body)["chaveAcesso"]
    assert_equal sent_xml, result.request_xml
    assert NfseNacional::Signer.verify!(result.request_xml, node: "infDPS")
    assert_empty result.errors
    assert_not result.retryable?
    assert_requested request
  end

  test "emite no leiaute rtc validando no XSD derivado" do
    rtc_xml = File.read(fixture_path("dps_rtc_homologacao.xml"))
    asked = nil
    dps = fake_dps(rtc_xml) { |leiaute| asked = leiaute }
    sent_xml = nil
    stub_request(:post, "#{BASE}/nfse").with { |req| sent_xml = unpack(JSON.parse(req.body).fetch("dpsXmlGZipB64")) }
      .to_return(status: 201, body: JSON.generate(chaveAcesso: KEY))

    assert_equal :issued, @client.emitir(dps, idempotency_key: "digest", leiaute: :rtc).status
    assert_equal :rtc, asked
    assert_includes sent_xml, "<finNFSe>0</finNFSe>"
    assert_raises(NfseNacional::Schema::Invalid) { @client.emitir(dps, idempotency_key: "digest") }
  end

  test "DPS fiscal inválida não é enviada" do
    @dps = fake_dps(@xml.sub("<nDPS>123456789012</nDPS>", "<nDPS>0</nDPS>"))
    assert_raises(NfseNacional::Schema::Invalid) { @client.emitir(@dps, idempotency_key: "digest") }
    assert_not_requested :post, "#{BASE}/nfse"
  end

  test "400 é rejeição definitiva com erros legíveis e pedido preservado" do
    stub_request(:post, "#{BASE}/nfse").to_return(status: 400, body: JSON.generate(erros: [{codigo: "E001", descricao: "DPS inválida"}]))
    result = @client.emitir(@dps, idempotency_key: "digest")
    assert_equal :rejected, result.status
    assert_equal ["E001 - DPS inválida"], result.errors
    assert_not result.retryable?
    assert NfseNacional::Signer.verify!(result.request_xml, node: "infDPS")
  end

  test "400 com chaves em maiúscula, como a Sefin devolve, mostra código e descrição" do
    body = {tipoAmbiente: 2, idDPS: "DPS123", erros: [{Codigo: "E0116", Descricao: "A IM deve ser informada", Complemento: "CNC"}]}
    stub_request(:post, "#{BASE}/nfse").to_return(status: 400, body: JSON.generate(body))
    result = @client.emitir(@dps, idempotency_key: "digest")
    assert_equal :rejected, result.status
    assert_equal ["E0116 - A IM deve ser informada (CNC)"], result.errors
  end

  test "erro singular de evento inclui código descrição e complemento" do
    stub_request(:post, "#{BASE}/nfse/#{KEY}/eventos").to_return(status: 400,
      body: JSON.generate(erro: {codigo: "E123", descricao: "Evento inválido", complemento: "Motivo não permitido"}))

    result = @client.cancelar(KEY, cnpj_autor: "12345678000195", motivo: "Erro na emissão da nota fiscal")

    assert_equal :rejected, result.status
    assert_equal ["E123 - Evento inválido (Motivo não permitido)"], result.errors
    assert_not result.retryable?
  end

  test "formatos inesperados de erros são ignorados sem falhar" do
    [
      ["hash", JSON.generate(erros: {codigo: "E123", descricao: "Não é uma lista"})],
      ["items", JSON.generate(erros: ["texto", 7, nil])]
    ].each do |key, body|
      stub_request(:post, "#{BASE}/nfse").with(headers: {"Idempotency-Key" => key}).to_return(status: 400, body: body)

      result = @client.emitir(@dps, idempotency_key: key)

      assert_equal :rejected, result.status
      assert_equal ["Resposta da Sefin (HTTP 400)"], result.errors
    end
  end

  test "403 preserva rejeição do certificado mesmo sem JSON" do
    stub_request(:post, "#{BASE}/nfse").to_return(status: 403, body: "Forbidden")
    result = @client.emitir(@dps, idempotency_key: "digest")
    assert_equal :rejected, result.status
    assert_includes result.errors, "Certificado recusado pela Sefin (403)"
    assert_not result.retryable?
  end

  test "500 e redirecionamento são erros retentáveis sem seguir Location" do
    [500, 302].each do |status|
      stub_request(:post, "#{BASE}/nfse").to_return(status: status, body: "indisponível", headers: {"Location" => "https://example.com"})
      result = @client.emitir(@dps, idempotency_key: "digest")
      assert_equal :error, result.status
      assert_equal status, result.http_status
      assert result.retryable?
    end
  end

  test "timeout DNS TLS conexão e reset resultam em erro retentável" do
    [Net::ReadTimeout, Net::OpenTimeout, SocketError, OpenSSL::SSL::SSLError, Errno::ECONNREFUSED, Errno::ECONNRESET,
      Errno::ENETUNREACH, Errno::EADDRNOTAVAIL, Errno::EHOSTUNREACH, Net::HTTPBadResponse, Net::ProtocolError].each do |error|
      stub_request(:post, "#{BASE}/nfse").to_raise(error)
      result = @client.emitir(@dps, idempotency_key: "digest")
      assert_equal :error, result.status
      assert_nil result.http_status
      assert result.retryable?
      assert_not_empty result.errors
      assert NfseNacional::Signer.verify!(result.request_xml, node: "infDPS")
    end
  end

  test "consulta 200 encontra chave 404 não encontra e demais respostas são erro" do
    [200, 404, 400, 500].each do |status|
      stub_request(:get, "#{BASE}/dps/DPS123").to_return(status: status, body: JSON.generate(chaveAcesso: KEY))
      result = @client.consultar_dps("DPS123")
      assert_equal({200 => :issued, 404 => :not_found, 400 => :rejected}.fetch(status, :error), result.status)
      if status == 200
        assert_equal KEY, result.access_key
      else
        assert_nil result.access_key
      end
      assert_equal status == 500, result.retryable?
    end
  end

  test "sucesso com JSON inválido ou XML compactado corrompido é erro retentável" do
    ["não é JSON", "[]", JSON.generate(nfseXmlGZipB64: "inválido")].each do |body|
      stub_request(:post, "#{BASE}/nfse").to_return(status: 201, body: body)
      result = @client.emitir(@dps, idempotency_key: "digest")
      assert_equal :error, result.status
      assert result.retryable?
      assert_equal 201, result.http_status
      assert_equal body, result.body
      assert_not_empty result.request_xml
      assert_not_empty result.errors
    end
  end

  test "cancela com pedido válido no XSD antes da assinatura e idempotência estável" do
    requests = []
    event_xml = "<evento>cancelado</evento>"
    stub_request(:post, "#{BASE}/nfse/#{KEY}/eventos").with do |req|
      requests << req
      signed = unpack(JSON.parse(req.body).fetch("pedidoRegistroEventoXmlGZipB64"))
      NfseNacional::Signer.verify!(signed, node: "infPedReg")
      doc = Nokogiri::XML(signed)
      doc.xpath("//*[local-name()='Signature']").remove
      NfseNacional::Schema.validate_cancelamento!(doc.to_xml)
      true
    end.to_return(status: 201, body: JSON.generate(eventoXmlGZipB64: pack(event_xml)))
    travel_to Time.new(2026, 10, 16, 12, 30, 0, "-03:00") do
      2.times do
        result = @client.cancelar(KEY, cnpj_autor: "12345678000195", motivo: "Erro na emissão da nota fiscal")
        assert_equal :issued, result.status
        assert_equal event_xml, result.event_xml
        assert NfseNacional::Signer.verify!(result.request_xml, node: "infPedReg")
        travel 60
      end
    end
    keys = requests.map { |req| req.headers.fetch("Idempotency-Key") }
    assert_match(/\A[0-9a-f]{64}\z/, keys.first)
    assert_equal keys.first, keys.last
  end

  test "cancelamento inválido não faz POST" do
    assert_raises(NfseNacional::Schema::Invalid) { @client.cancelar(KEY, cnpj_autor: "12345678000195", motivo: "curto") }
    assert_not_requested :post, "#{BASE}/nfse/#{KEY}/eventos"
  end

  test "produção usa as bases próprias e ambiente desconhecido é recusado" do
    client = NfseNacional::Client.new(certificado: @certificate, ambiente: :producao)
    request = stub_request(:get, "https://sefin.nfse.gov.br/SefinNacional/dps/DPS123").to_return(status: 404)
    assert_equal :not_found, client.consultar_dps("DPS123").status
    assert_requested request
    assert_raises(KeyError) { NfseNacional::Client.new(certificado: @certificate, ambiente: :invalid) }
  end

  test "transporte configura mTLS verificação de servidor e timeouts" do
    captured = nil
    original = Net::HTTP.method(:new)
    Net::HTTP.stub(:new, ->(*args) { captured = original.call(*args) }) do
      stub_request(:get, "#{BASE}/dps/DPS123").to_return(status: 404)
      client = NfseNacional::Client.new(certificado: @certificate, ambiente: :homologacao, open_timeout: 7, read_timeout: 31)
      client.consultar_dps("DPS123")
    end
    assert captured.use_ssl?
    assert_equal OpenSSL::SSL::VERIFY_PEER, captured.verify_mode
    assert_equal @certificate.certificate, captured.cert
    assert_equal @certificate.key, captured.key
    assert_equal 7, captured.open_timeout
    assert_equal 31, captured.read_timeout
    assert_equal 0, captured.max_retries
  end

  test "consulta NFSe pela chave escapada e recupera XML compactado" do
    request = stub_request(:get, "#{BASE}/nfse/chave%2Fcom%20espaco")
      .to_return(status: 200, body: JSON.generate(chaveAcesso: "chave/com espaco", nfseXmlGZipB64: pack("<NFSe>recuperada</NFSe>")))

    result = @client.consultar_nfse("chave/com espaco")

    assert_equal :issued, result.status
    assert_equal "<NFSe>recuperada</NFSe>", result.nfse_xml
    assert_requested request
  end

  test "consulta NFSe distingue ausência de erro transitório" do
    [404, 500].each do |status|
      stub_request(:get, "#{BASE}/nfse/#{KEY}").to_return(status: status, body: "{}")

      result = @client.consultar_nfse(KEY)

      assert_equal({404 => :not_found, 500 => :error}.fetch(status), result.status)
      assert_equal(status == 500, result.retryable?)
    end
  end

  test "produção usa a base própria e ambiente desconhecido é recusado" do
    client = NfseNacional::Client.new(certificado: @certificate, ambiente: :producao)
    request = stub_request(:get, "https://sefin.nfse.gov.br/SefinNacional/dps/DPS123").to_return(status: 404)
    assert_equal :not_found, client.consultar_dps("DPS123").status
    assert_requested request
    assert_raises(KeyError) { NfseNacional::Client.new(certificado: @certificate, ambiente: :invalid) }
  end

  test "E1235 da Sefin vira rejected com o código" do
    stub_request(:post, "#{BASE}/nfse").to_return(status: 400,
      body: JSON.generate(erros: [{Codigo: "E1235", Descricao: "Falha no esquema XML do DF-e.", Complemento: "invalid child element 'cLocEmi'"}]))
    result = @client.emitir(@dps, idempotency_key: "digest")
    assert_equal :rejected, result.status
    assert_match(/\AE1235 - /, result.errors.first)
  end

  test "cancelamento sai com o ver_aplic do Client" do
    client = NfseNacional::Client.new(certificado: @certificate, ambiente: :homologacao, ver_aplic: "NotaApp-1")
    sent = nil
    stub_request(:post, %r{/nfse/#{"1" * 50}/eventos}).to_return do |request|
      sent = request.body
      {status: 201, body: {"chaveAcesso" => "1" * 50}.to_json}
    end
    client.cancelar("1" * 50, cnpj_autor: "12345678000195", motivo: "Erro na emissão da nota de teste")
    event = Zlib::GzipReader.wrap(StringIO.new(Base64.strict_decode64(JSON.parse(sent)["pedidoRegistroEventoXmlGZipB64"])), &:read)
    assert_includes event, "<verAplic>NotaApp-1</verAplic>"
  end

  test "consulta com 403 é rejeição, não erro retentável" do
    stub_request(:get, %r{/dps/}).to_return(status: 403, body: {"erros" => [{"Codigo" => "E2403", "Descricao" => "Consulta não permitida"}]}.to_json)
    result = NfseNacional::Client.new(certificado: @certificate).consultar_dps("DPS123")
    assert_equal :rejected, result.status
    refute result.retryable?
  end

  [408, 429].each do |code|
    test "POST com #{code} é erro retentável" do
      stub_request(:post, %r{/nfse\z}).to_return(status: code, body: "{}")
      result = NfseNacional::Client.new(certificado: @certificate).emitir(@dps, idempotency_key: "chave")
      assert_equal :error, result.status
      assert result.retryable?
    end
  end

  private

  def pack(xml)
    output = StringIO.new("".b)
    Zlib::GzipWriter.wrap(output) { |gzip| gzip.write(xml) }
    Base64.strict_encode64(output.string)
  end

  def fake_dps(xml, &on_call)
    Object.new.tap { |dps|
      dps.define_singleton_method(:to_xml) { |leiaute: :atual|
        on_call&.call(leiaute)
        xml
      }
    }
  end

  def unpack(value)
    Zlib::GzipReader.wrap(StringIO.new(Base64.strict_decode64(value)), &:read)
  end
end
