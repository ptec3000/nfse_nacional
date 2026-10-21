module NfseNacional
  class Result
    attr_reader :status, :access_key, :nfse_xml, :event_xml, :request_xml, :http_status, :body, :errors

    def initialize(status:, access_key: nil, nfse_xml: nil, event_xml: nil, request_xml: nil, http_status: nil, body: nil,
      errors: [])
      @status = status
      @access_key = access_key
      @nfse_xml = nfse_xml
      @event_xml = event_xml
      @request_xml = request_xml
      @http_status = http_status
      @body = body
      @errors = errors
    end

    def retryable?
      status == :error
    end
  end
end
