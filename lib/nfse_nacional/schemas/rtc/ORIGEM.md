# XSD do leiaute `:rtc` (NT 009, versão 1.01)

Esquemas oficiais da **produção restrita** da NFS-e Nacional, sem alterações:

- Pacote: `esquemas_prod_restrita_20261020.zip`, publicado em 20/10/2026 em
  https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/producao-restrita
- SHA-256 do pacote: `25fdcecc651a67a216496ab10d7566631e6ed10f721e37d62c7845dadb0ea267`
- Arquivos usados: `DPS_v1.01.xsd`, `tiposComplexos_v1.01.xsd`, `tiposSimples_v1.01.xsd`, `xmldsig-core-schema.xsd`.

Eles substituem a cópia derivada do pacote de 09/02/2026 que esta gem usava (o antigo `PATCH.md`): o pacote oficial
já traz `finNFSe` em `infDPS`, o `cNBS` antes de `xDescServ`, `CST`/`cClassTrib` direto em `trib` e o padrão de série
que aceita até 89999 (`[0-9]{1,4}|[0-8][0-9]{4}`). O grupo `vDedRed` deu lugar a `vAjusteBC`.

Para atualizar: baixe o pacote novo, substitua os arquivos, atualize este arquivo e rode `bundle exec rake test`.
