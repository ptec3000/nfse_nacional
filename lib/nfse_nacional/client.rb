require "net/http"
require "json"
require "zlib"
require "stringio"
require "base64"
require "digest"
require "openssl"

module NfseNacional
  class Client
    SEFIN_URLS = {
      producao: "https://sefin.nfse.gov.br/SefinNacional",
      homologacao: "https://sefin.producaorestrita.nfse.gov.br/SefinNacional"
    }.freeze
    NETWORK_ERRORS = [Timeout::Error, SocketError, OpenSSL::SSL::SSLError, IOError,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ENETUNREACH, Errno::EADDRNOTAVAIL, Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT, Errno::EPIPE, Net::HTTPBadResponse, Net::ProtocolError].freeze

    def initialize(certificado:, ambiente: :homologacao, open_timeout: 10, read_timeout: 60,
      ver_aplic: NfseNacional::VER_APLIC)
      @ver_aplic = NfseNacional.ver_aplic!(ver_aplic)
      @certificado = certificado
      @ambiente = ambiente
      @base_url = SEFIN_URLS.fetch(ambiente)
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def emitir(dps, idempotency_key:, leiaute: :atual)
      xml = dps.to_xml(leiaute: leiaute)
      Schema.validate_dps!(xml, leiaute: leiaute)
      signed = Signer.new(@certificado).sign(xml, node: "infDPS")
      perform("/nfse", request_xml: signed, idempotency_key: idempotency_key,
        payload: {dpsXmlGZipB64: gzip_base64(signed)})
    end

    def consultar_dps(dps_id)
      perform("/dps/#{URI.encode_uri_component(dps_id)}", lookup: true)
    end

    def consultar_nfse(access_key)
      perform("/nfse/#{URI.encode_uri_component(access_key)}", lookup: true)
    end

    def cancelar(access_key, cnpj_autor:, motivo:, codigo_motivo: "1", numero_pedido: 1)
      xml = Cancelamento.new(access_key: access_key, ambiente: @ambiente, cnpj_autor: cnpj_autor,
        motivo: motivo, codigo_motivo: codigo_motivo, numero_pedido: numero_pedido, ver_aplic: @ver_aplic).to_xml
      Schema.validate_cancelamento!(xml)
      signed = Signer.new(@certificado).sign(xml, node: "infPedReg")
      # Exclui dhEvento para manter a mesma chave em tentativas posteriores.
      key = Digest::SHA256.hexdigest(JSON.generate([@ambiente, access_key, cnpj_autor.to_s.gsub(/\D/, ""), codigo_motivo.to_s, motivo, numero_pedido.to_s]))
      perform("/nfse/#{URI.encode_uri_component(access_key)}/eventos", request_xml: signed, idempotency_key: key,
        payload: {pedidoRegistroEventoXmlGZipB64: gzip_base64(signed)})
    end

    private

    def perform(path, payload: nil, request_xml: nil, idempotency_key: nil, lookup: false)
      response = request(URI("#{@base_url}#{path}"), payload: payload, idempotency_key: idempotency_key)
      result_from(response, request_xml: request_xml, lookup: lookup)
    rescue *NETWORK_ERRORS => error
      Result.new(status: :error, request_xml: request_xml, errors: ["Falha de comunicação com a Sefin (#{error.class})"])
    end

    def request(uri, payload: nil, idempotency_key: nil)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.cert = @certificado.certificate
      http.key = @certificado.key
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.open_timeout = @open_timeout
      http.read_timeout = @read_timeout
      http.max_retries = 0
      req = payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req["Accept"] = "application/json"
      if payload
        raise ArgumentError, "Idempotency-Key obrigatório" if idempotency_key.to_s.strip.empty?
        req["Content-Type"] = "application/json"
        req["Idempotency-Key"] = idempotency_key
        req.body = JSON.generate(payload)
      end
      http.request(req)
    end

    def result_from(response, request_xml:, lookup:)
      code = response.code.to_i
      status = if lookup
        if code == 200
          :issued
        elsif code == 404
          :not_found
        elsif code.between?(400, 499) && ![408, 429].include?(code)
          :rejected
        else
          :error
        end
      elsif code.between?(200, 299)
        :issued
      elsif code.between?(400, 499) && ![408, 429].include?(code)
        :rejected
      else
        :error
      end
      data = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
      if status == :issued && !data.is_a?(Hash)
        return Result.new(status: :error, request_xml: request_xml, http_status: code, body: response.body,
          errors: ["JSON inválido na resposta da Sefin"])
      end
      data = {} unless data.is_a?(Hash)
      error_items = data["erros"].is_a?(Array) ? data["erros"] : [data["erro"]]
      errors = error_items.filter_map do |error|
        next unless error.is_a?(Hash)

        # A Sefin devolve "Codigo"/"Descricao"; a documentação mostra em minúsculas.
        error = error.transform_keys { |key| key.to_s.downcase }
        message = [error["codigo"], error["descricao"] || error["mensagem"]].compact.join(" - ")
        complemento = error["complemento"]
        if complemento && !complemento.to_s.empty?
          message = message.empty? ? "(#{complemento})" : "#{message} (#{complemento})"
        end
        message unless message.empty?
      end
      errors << "Certificado recusado pela Sefin (403)" if code == 403
      errors << "Resposta da Sefin (HTTP #{code})" if errors.empty? && %i[error rejected].include?(status)
      nfse_xml = nil
      event_xml = nil
      if status == :issued && data["nfseXmlGZipB64"]
        nfse_xml = Zlib::GzipReader.wrap(StringIO.new(Base64.strict_decode64(data["nfseXmlGZipB64"])), &:read)
      end
      if status == :issued && data["eventoXmlGZipB64"]
        event_xml = Zlib::GzipReader.wrap(StringIO.new(Base64.strict_decode64(data["eventoXmlGZipB64"])), &:read)
      end
      Result.new(status: status, access_key: (data["chaveAcesso"] if status == :issued), nfse_xml: nfse_xml,
        event_xml: event_xml, request_xml: request_xml, http_status: code, body: response.body, errors: errors)
    rescue Zlib::Error, ArgumentError, EOFError
      Result.new(status: :error, request_xml: request_xml, http_status: code, body: response.body,
        errors: ["XML compactado inválido na resposta da Sefin"])
    end

    def gzip_base64(xml)
      output = StringIO.new("".b)
      Zlib::GzipWriter.wrap(output) { |gzip| gzip.write(xml) }
      Base64.strict_encode64(output.string)
    end
  end
end
