# Schemas NFS-e Nacional

Arquivos oficiais, sem alterações, do diretório `Schemas/1.00/` do pacote
[NFSe-ESQUEMAS_XSD-v1.01-20260209.zip](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/nfse-esquemas_xsd-v1-01-20260209.zip),
listado na [documentação atual de produção](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual).

Pacote: versão 1.01, data nominal 2026-02-09; arquivos no ZIP datados de
2026-02-11 11:42. Download e conferência: 2026-10-16.
SHA-256 do ZIP: `e7935cbd9470527c6cc32984c1b2263e614183bf0139ce2733eaaed2de9a8072`.

Usamos o conjunto **1.00** porque a DPS declara
`versao="1.00"`. Esse conjunto aceita o golden com `tribFed` sem exceções.
Incluímos os oito XSDs de DPS, NFS-e e eventos previstos na tarefa;
os schemas de CNC, sem uso nesta biblioteca, não foram copiados.

`1.01/` traz os quatro XSDs de DPS do diretório `Schemas/1.01/` do mesmo pacote, sem
alterações. `rtc/` é derivado deles para o leiaute que a homologação aceita desde
19/10/2026 (ver `rtc/PATCH.md`). `Schema.validate_dps!(xml, leiaute: :rtc)` usa `rtc/`;
o leiaute `:atual` continua no conjunto 1.00 acima.

O `dhEmi` deve manter o fuso `-03:00`: use `Time.current` com
`config.time_zone = "Brasilia"`. Com `+00:00`, a Sefin devolve E0008
de forma intermitente.
