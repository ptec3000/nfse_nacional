require "nokogiri"

module NfseNacional
  module Schema
    class Invalid < StandardError
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        messages = errors.map(&:to_s)
        super(messages.join("\n"))
      end
    end

    DPS_SCHEMAS = {atual: "schemas/DPS_v1.00.xsd", rtc: "schemas/rtc/DPS_v1.01.xsd"}.freeze

    def self.validate_dps!(xml, leiaute: :atual)
      validate!(xml, dps_schema(leiaute))
    end

    def self.validate_cancelamento!(xml)
      validate!(xml, cancelamento_schema)
    end

    def self.validate!(xml, schema)
      document = Nokogiri::XML(xml) { |config| config.strict.nonet }
      errors = schema.validate(document)
      raise Invalid.new(errors) unless errors.empty?
    rescue Nokogiri::XML::SyntaxError => error
      raise Invalid.new([error])
    end

    def self.dps_schema(leiaute)
      path = DPS_SCHEMAS.fetch(leiaute) { raise ArgumentError, "Leiaute desconhecido: #{leiaute.inspect}" }
      @dps_schemas ||= {}
      @dps_schemas[leiaute] ||= File.open(File.expand_path(path, __dir__)) { |file| Nokogiri::XML::Schema(file) }
    end

    def self.cancelamento_schema
      @cancelamento_schema ||= File.open(File.expand_path("schemas/pedRegEvento_v1.00.xsd", __dir__)) do |file|
        Nokogiri::XML::Schema(file)
      end
    end
    private_class_method :dps_schema, :cancelamento_schema, :validate!
  end
end
