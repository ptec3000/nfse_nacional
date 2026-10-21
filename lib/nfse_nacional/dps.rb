require "date"
require "bigdecimal"
require "nokogiri"

module NfseNacional
  class Dps
    LEIAUTES = %i[atual rtc].freeze
    IBS_CBS_KEYS = %i[c_ind_op cst c_class_trib].freeze

    def initialize(ambiente:, prestador:, tomador:, servico:, valores:, competencia:, serie:, numero:,
      versao: "1.00", ver_aplic: NfseNacional::VER_APLIC, tp_emit: "1", now: Time.now, ibs_cbs: nil)
      @ambiente = AMBIENTES.fetch(ambiente)
      @prestador = prestador
      @tomador = tomador
      @servico = servico
      @valores = valores
      @competencia = competencia
      @serie = serie
      @numero = numero
      @versao = versao
      @ver_aplic = NfseNacional.ver_aplic!(ver_aplic)
      @tp_emit = tp_emit
      @now = now
      @ibs_cbs = ibs_cbs

      if foreign_tomador? && blank_string?(tomador[:nome])
        raise ArgumentError, "Tomador incompleto: informe o nome do tomador estrangeiro"
      end
      if normalize_document(tomador&.[](:documento)) && blank_string?(tomador[:nome])
        raise ArgumentError, "Tomador incompleto: informe o nome quando houver CPF/CNPJ"
      end
    end

    def id
      document = normalize_document(@prestador[:cnpj]).to_s
      inscription_type = (document.length == 14) ? "2" : "1"
      municipality = @prestador[:municipio_ibge].to_s.gsub(/\D/, "").rjust(7, "0")
      series = @serie.to_s.gsub(/\D/, "").rjust(5, "0")
      number = @numero.to_s.gsub(/\D/, "").rjust(15, "0")
      "DPS#{municipality}#{inscription_type}#{document.rjust(14, "0")}#{series}#{number}"
    end

    def ibs_cbs_configured? = IBS_CBS_KEYS.all? {|key| !@ibs_cbs.to_h[key].to_s.strip.empty?}

    # :rtc é o leiaute que a homologação exige desde 19/10/2026 (finNFSe e grupo IBSCBS, NT 009);
    # :atual é o de produção até ela virar.
    def to_xml(leiaute: :atual)
      raise ArgumentError, "Leiaute desconhecido: #{leiaute.inspect}" unless LEIAUTES.include?(leiaute)

      rtc = leiaute == :rtc
      raise IbsCbsNaoConfigurado if rtc && !ibs_cbs_configured?

      service_value = format_decimal(@valores[:valor])

      builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
        xml.DPS("xmlns" => "http://www.sped.fazenda.gov.br/nfse", "versao" => rtc ? "1.01" : @versao) do
          xml.infDPS("Id" => id) do
            xml.tpAmb @ambiente
            xml.dhEmi (@now - DHEMI_SAFETY_SECONDS).strftime("%Y-%m-%dT%H:%M:%S%:z")
            xml.verAplic @ver_aplic
            xml.serie @serie.to_s
            xml.nDPS @numero.to_s
            xml.dCompet @competencia.strftime("%Y-%m-%d")
            xml.tpEmit @tp_emit
            xml.finNFSe "0" if rtc
            xml.cLocEmi @prestador[:municipio_ibge]
            xml.prest do
              xml.CNPJ normalize_document(@prestador[:cnpj])
              xml.IM @prestador[:im] if @prestador[:im]
              xml.xNome @prestador[:nome] if @prestador[:nome] && @tp_emit.to_s != "1"
              xml.regTrib do
                xml.opSimpNac @prestador[:op_simp_nac]
                xml.regApTribSN @prestador[:reg_ap_trib_sn] if @prestador[:op_simp_nac].to_s == "3" && @prestador[:reg_ap_trib_sn]
                xml.regEspTrib @prestador[:reg_esp_trib]
              end
            end
            if foreign_tomador?
              xml.toma do
                if blank_string?(@tomador[:nif])
                  xml.cNaoNIF @tomador[:nao_nif] || "2"
                else
                  xml.NIF @tomador[:nif].to_s.strip
                end
                xml.xNome @tomador[:nome].to_s.strip
                address = @tomador.fetch(:endereco)
                xml.end_ do
                  xml.endExt do
                    xml.cPais address[:pais]
                    xml.cEndPost address[:codigo_postal]
                    xml.xCidade address[:cidade]
                    xml.xEstProvReg address[:estado]
                  end
                  xml.xLgr address[:logradouro]
                  xml.nro address[:numero]
                  xml.xCpl address[:complemento] unless blank_string?(address[:complemento])
                  xml.xBairro blank_string?(address[:bairro]) ? address[:estado] : address[:bairro]
                end
                xml.email @tomador[:email].to_s.strip unless blank_string?(@tomador[:email])
              end
            elsif (document = normalize_document(@tomador&.[](:documento)))
              xml.toma do
                if document.length == 11
                  xml.CPF document
                else
                  xml.CNPJ document
                end
                xml.xNome @tomador[:nome].to_s.strip
                xml.email @tomador[:email].to_s.strip unless blank_string?(@tomador[:email])
              end
            end
            xml.serv do
              xml.locPrest do
                if @servico[:pais_prestacao]
                  xml.cPaisPrestacao @servico[:pais_prestacao]
                elsif @servico[:municipio_prestacao_ibge]
                  xml.cLocPrestacao @servico[:municipio_prestacao_ibge]
                end
              end
              xml.cServ do
                xml.cTribNac @servico[:c_trib_nac]
                municipal_code = @servico[:c_trib_mun].to_s.gsub(/\D/, "")
                xml.cTribMun municipal_code if municipal_code.match?(/^\d{3}$/)
                # A homologação (rtc) exige o NBS antes da descrição desde 20/10/2026; o XSD 1.01 publicado o põe depois.
                xml.cNBS @servico[:nbs] if rtc && @servico[:nbs]
                xml.xDescServ @servico[:descricao]
                xml.cNBS @servico[:nbs] if !rtc && @servico[:nbs]
              end
              if (ext = @servico[:comercio_exterior])
                xml.comExt do
                  xml.mdPrestacao ext[:modo_prestacao]
                  xml.vincPrest ext[:vinculo]
                  xml.tpMoeda ext[:moeda]
                  xml.vServMoeda format_decimal(ext[:valor_moeda])
                  xml.mecAFComexP ext[:mec_prestador]
                  xml.mecAFComexT ext[:mec_tomador]
                  xml.movTempBens ext[:mov_temp_bens]
                  xml.mdic ext[:mdic]
                end
              end
            end
            xml.valores do
              xml.vServPrest do
                xml.vServ service_value
              end
              xml.trib do
                xml.tribMun do
                  xml.tribISSQN @valores[:trib_issqn]
                  xml.cPaisResult @valores[:pais_resultado] if @valores[:pais_resultado]
                  xml.tpRetISSQN @valores[:tp_ret_issqn]
                end
                if (pis_cofins = @valores.fetch(:pis_cofins))
                  base = format_decimal(pis_cofins[:base] || service_value)
                  pis_rate = format_decimal(pis_cofins[:aliq_pis] || "0.65")
                  cofins_rate = format_decimal(pis_cofins[:aliq_cofins] || "3.00")
                  pis_value = format_decimal(BigDecimal(base) * BigDecimal(pis_rate) / 100)
                  cofins_value = format_decimal(BigDecimal(base) * BigDecimal(cofins_rate) / 100)

                  xml.tribFed do
                    xml.piscofins do
                      xml.CST pis_cofins[:cst]
                      xml.vBCPisCofins base
                      xml.pAliqPis pis_rate
                      xml.pAliqCofins cofins_rate
                      xml.vPis pis_value
                      xml.vCofins cofins_value
                      xml.tpRetPisCofins pis_cofins[:tp_ret]
                    end
                  end
                end
                xml.totTrib do
                  if (percentages = @valores[:tot_trib_percentual])
                    xml.pTotTrib do
                      xml.pTotTribFed format_decimal(percentages[:fed])
                      xml.pTotTribEst format_decimal(percentages[:est])
                      xml.pTotTribMun format_decimal(percentages[:mun])
                    end
                  elsif (tot_trib = @valores[:tot_trib])
                    if tot_trib.key?(:ind_tot_trib)
                      xml.indTotTrib tot_trib[:ind_tot_trib]
                    else
                      xml.pTotTribSN format_decimal(tot_trib[:p_tot_trib_sn])
                    end
                  else
                    xml.pTotTribSN format_decimal(@valores[:p_tot_trib_sn] || "6.00")
                  end
                end
              end
            end
            if rtc
              xml.IBSCBS do
                xml.cIndOp @ibs_cbs[:c_ind_op].to_s
                xml.indDest "0"
                xml.valores do
                  xml.trib do
                    xml.CST @ibs_cbs[:cst].to_s
                    xml.cClassTrib @ibs_cbs[:c_class_trib].to_s
                  end
                end
              end
            end
          end
        end
      end
      builder.to_xml(save_with: Nokogiri::XML::Node::SaveOptions::AS_XML)
    end

    private

    def blank_string?(value)
      value.to_s.strip.empty?
    end

    def foreign_tomador?
      country = @tomador&.dig(:endereco, :pais).to_s.upcase
      !country.empty? && country != "BR"
    end

    def normalize_document(value)
      digits = value.to_s.gsub(/\D/, "")
      digits.empty? ? nil : digits
    end

    def format_decimal(value)
      format("%.2f", BigDecimal(value.to_s).round(2))
    end
  end
end
