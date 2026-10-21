# XSD RTC (derivado, experimental)

Derivado de `../1.01/` (pacote oficial NFSe-ESQUEMAS_XSD-v1.01-20260209.zip,
SHA-256 e7935cbd9470527c6cc32984c1b2263e614183bf0139ce2733eaaed2de9a8072).
`tiposComplexos_v1.01.xsd` e `tiposSimples_v1.01.xsd` mudam.
`DPS_v1.01.xsd` e `xmldsig-core-schema.xsd` são idênticos ao oficial.

Por quê: desde 19/10/2026 a homologação da Sefin (SefinNacional_1.6.0) aceita uma
ordem que não é a do XSD 1.01 publicado. Ela foi testada com envio real em 20/10/2026.

Diff em relação ao oficial:
1. `finNFSe` sai de `TCRTCInfoIBSCBS` e entra em `TCInfDPS`, depois de `cMotivoEmisTI`.
2. `TCRTCInfoTributosIBSCBS` deixa de ter `gIBSCBS`: `CST`, `cClassTrib` e os
   opcionais de `TCRTCInfoTributosSitClas` ficam direto em `trib`.
3. `TSSerieDPS` (tiposSimples): o pattern oficial `^0{0,4}\d{1,5}$` usa `^`/`$`, que em XML Schema são literais; o libxml recusa qualquer série. O derivado usa `0{0,4}\d{1,5}`.
4. `TCCServ`: `xDescServ` passa para o fim, depois de `cNBS` e `cIntContrib`
   (ordem: `cTribNac`, `cTribMun`, `cNBS`, `cIntContrib`, `xDescServ`). A homologação
   mudou isso em 20/10/2026, entre 15h e 16h, sem aviso: o XML aceito às 15h passou a
   voltar E1235 ("invalid child element 'cNBS'"). Testado com envio real no mesmo dia.

É um contrato experimental. Quando a Sefin publicar o XSD que bate com o que ela
aceita, troque este diretório pelo oficial e apague este arquivo.
