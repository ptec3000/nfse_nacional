require_relative "test_helper"
require "webmock/minitest"

WebMock.disable_net_connect!

class ParametrizacaoMunicipalTest < NfseNacional::TestCase
  BASE = "https://adn.producaorestrita.nfse.gov.br"

  setup do
    @certificate = NfseNacional::Certificado.new(pfx: NfseTestCertificate.pfx, senha: "teste")
    @client = NfseNacional::Client.new(certificado: @certificate)
  end

  test "histórico aceita código com ou sem pontos e extrai a lista" do
    aliquotas = [{"Incidencia" => "SIM", "Aliq" => 5.0, "DtIni" => "2022-10-25T00:00:00", "DtFim" => nil}]
    stub_request(:get, url("001")).with(headers: {"Accept" => "application/json"}).to_return(
      status: 200, body: JSON.generate(aliquotas: {"17.11.01.001" => aliquotas}, mensagem: "Histórico encontrado")
    )
    %w[171101001 17.11.01.001].each do |codigo|
      assert_equal aliquotas, @client.historico_aliquotas(municipio_ibge: "3106200", codigo_servico: codigo)
    end
    assert_requested :get, url("001"), times: 2
  end

  test "histórico inexistente retorna nil e lista vazia permanece vazia" do
    answer("001", 404)
    assert_nil historico
    stub_request(:get, url("001")).to_return(status: 200, body: JSON.generate(aliquotas: {"17.11.01.001" => []}))
    assert_equal [], historico
  end

  test "histórico sinaliza HTTP rede e resposta inválida sem expor detalhes privados" do
    [400, 403, 500, :timeout, :network, :json, :shape].each do |failure|
      WebMock.reset!
      request = stub_request(:get, url("001"))
      case failure
      when :timeout then request.to_timeout
      when :network then request.to_raise(SocketError.new("certificado privado"))
      when :json then request.to_return(status: 200, body: "inválido")
      when :shape then request.to_return(status: 200, body: '{"aliquotas":null}')
      else request.to_return(status: failure)
      end
      error = assert_raises(NfseNacional::Error) { historico }
      assert_match(/ADN/, error.message)
      refute_match(/privado/, error.message)
    end
  end

  test "produção usa o host ADN de produção" do
    client = NfseNacional::Client.new(certificado: @certificate, ambiente: :producao)
    stub_request(:get, url("001").sub("adn.producaorestrita", "adn")).to_return(status: 404)
    assert_nil client.historico_aliquotas(municipio_ibge: "3106200", codigo_servico: "171101001")
  end

  test "000 dispensa código e encerra a sondagem" do
    answer("000", 200)
    result = lookup
    assert_instance_of NfseNacional::CodigosMunicipais, result
    refute result.exige?
    assert_empty result.codigos
    assert_requested :get, %r{/historicoaliquotas}, times: 1
  end

  test "coleta um ou vários códigos em ordem respeitando ate" do
    [["001"], %w[001 003]].each do |codes|
      WebMock.reset!
      seen = []
      stub_request(:get, %r{/historicoaliquotas}).to_return do |request|
        code = request.uri.path.split(".").last.split("/").first
        seen << code
        {status: codes.include?(code) ? 200 : 404}
      end
      result = lookup(c_trib_nac: "17.11.01", ate: 3)
      assert result.exige?
      assert_equal codes, result.codigos
      assert_equal %w[000 001 002 003], seen
    end
  end

  test "todos os 404 são desconhecidos com dez sondagens por padrão" do
    stub_request(:get, %r{/historicoaliquotas}).to_return(status: 404)
    assert_nil lookup
    assert_requested :get, %r{/historicoaliquotas}, times: 11
  end

  test "falhas auxiliares retornam nil e não repetem requisições" do
    [500, 400, :timeout, :network, :other].each do |failure|
      WebMock.reset!
      request = stub_request(:get, url("000"))
      case failure
      when :timeout then request.to_timeout
      when :network then request.to_raise(SocketError)
      when :other then request.to_raise(Zlib::DataError)
      else request.to_return(status: failure)
      end
      assert_nil lookup
      assert_requested :get, url("000"), times: 1
    end
  end

  test "falha intermediária descarta a lista parcial" do
    answer("000", 404)
    answer("001", 200)
    answer("002", 500)
    assert_nil lookup
    assert_requested :get, %r{/historicoaliquotas}, times: 3
  end

  test "resposta positiva depois do prazo é descartada" do
    elapsed = 0.0
    stub_request(:get, url("000")).to_return do
      elapsed = 8.1
      {status: 200}
    end
    Process.stub(:clock_gettime, ->(*) { elapsed }) { assert_nil lookup }
  end

  test "prazo total acumula sondagens e descarta lista parcial" do
    elapsed = 0.0
    stub_request(:get, %r{/historicoaliquotas}).to_return do |request|
      elapsed += 3.0
      {status: request.uri.path.include?(".001/") ? 200 : 404}
    end
    Process.stub(:clock_gettime, ->(*) { elapsed }) { assert_nil lookup }
    assert_requested :get, %r{/historicoaliquotas}, times: 3
  end

  test "consulta exata retorna true false ou nil inclusive fora da faixa sondada" do
    [[200, true], [404, false], [500, nil]].each do |status, expected|
      stub_request(:get, url("099")).to_return(status: status)
      result = existe(c_trib_mun: "099")
      expected.nil? ? assert_nil(result) : assert_equal(expected, result)
    end
    stub_request(:get, url("099")).to_timeout
    assert_nil existe(c_trib_mun: "099")
  end

  test "consulta exata também descarta resposta tardia e aceita prazo próprio" do
    elapsed = 0.0
    stub_request(:get, url("001")).to_return do
      elapsed = 1.1
      {status: 200}
    end
    Process.stub(:clock_gettime, ->(*) { elapsed }) { assert_nil existe(prazo: 1) }
  end

  test "sondagens reutilizam conexão mTLS e reduzem limites ao prazo restante" do
    elapsed = 0.0
    connections = []
    limits = []
    original_new = Net::HTTP.method(:new)
    factory = lambda do |*args|
      http = original_new.call(*args)
      connections << http
      http
    end
    stub_request(:get, %r{/historicoaliquotas}).to_return do |request|
      http = connections.last
      assert http.started?
      assert http.use_ssl?
      assert_equal @certificate.certificate, http.cert
      assert_equal @certificate.key, http.key
      assert_equal OpenSSL::SSL::VERIFY_PEER, http.verify_mode
      assert_equal 0, http.max_retries
      limits << [http.open_timeout, http.read_timeout, http.write_timeout]
      elapsed += 2.5
      {status: request.uri.path.include?(".001/") ? 200 : 404}
    end
    Process.stub(:clock_gettime, ->(*) { elapsed }) do
      Net::HTTP.stub(:new, factory) do
        assert_equal ["001"], lookup(ate: 2, prazo: 7.75).codigos
      end
    end
    assert_equal 1, connections.size
    refute connections.first.started?
    assert_equal [[3, 3, 3], [3, 3, 3], [2.75, 2.75, 2.75]], limits
  end

  test "operação pendente é interrompida pelo prazo total" do
    stub_request(:get, url("000")).to_return do
      sleep 0.1
      {status: 200}
    end
    assert_nil lookup(prazo: 0.01)
  end

  test "entradas inválidas não acessam a rede" do
    assert_raises(ArgumentError) { historico(codigo_servico: "../") }
    assert_raises(ArgumentError) { historico(municipio_ibge: "../") }
    assert_nil lookup(c_trib_nac: "../")
    assert_nil lookup(ate: 1000)
    assert_nil lookup(ate: 0)
    assert_nil lookup(prazo: 0)
    assert_nil existe(c_trib_mun: "../")
    assert_not_requested :get, %r{/parametrizacao/}
  end

  private

  def url(code)
    "#{BASE}/parametrizacao/3106200/17.11.01.#{code}/historicoaliquotas"
  end

  def answer(code, status)
    stub_request(:get, url(code)).to_return(status: status)
  end

  def historico(**kwargs)
    @client.historico_aliquotas(municipio_ibge: "3106200", codigo_servico: "171101001", **kwargs)
  end

  def lookup(**kwargs)
    @client.codigos_municipais(municipio_ibge: "3106200", c_trib_nac: "171101", **kwargs)
  end

  def existe(**kwargs)
    @client.codigo_municipal_existe?(municipio_ibge: "3106200", c_trib_nac: "171101", c_trib_mun: "001", **kwargs)
  end
end
