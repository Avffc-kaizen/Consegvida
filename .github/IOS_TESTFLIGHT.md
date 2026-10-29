# ConsegVida — envio manual ao TestFlight

Esta automação prepara e envia a versão existente do aplicativo pelo fluxo oficial do Xcode. A preparação foi feita sobre `main` em `5ea0ce94b2ad7f1c602bf362629f97d7843aae04`. Nenhuma assinatura, credencial, criação de certificado/perfil, execução do workflow ou upload Apple foi realizada durante essa preparação.

## O que já foi validado

O run `40914666442` comprovou build do app, testes do domínio, abertura no simulador e archive de device sem assinatura, com Xcode 26.6 e SDK iOS 26.5. O projeto gerado pelo xtool 1.24.0 preserva os pacotes locais e contém ícones processados, manifesto de privacidade e conteúdo canônico. O envio Apple continua sem validação real até a primeira execução autorizada com uma equipe elegível.

Este workflow não depende dos artifacts antigos de retenção curta. Após validar a configuração e os registros Apple, chama `mobile/ios/ci-archive-unsigned.sh`, reaproveita o projeto portátil gerado e cria **outro archive assinado para desenvolvimento** com a equipe selecionada. Só então executa distribuição com cloud signing. O archive unsigned não é tratado como se já estivesse pronto para exportação assinada.

## Pré-condições da conta

- Apple Developer Program ativo, contratos vigentes e acesso ao App Store Connect.
- App record existente no App Store Connect e App ID explícito já registrado com o bundle ID presente em `mobile/ios/xtool.yml`. Atualmente é `com.consegvida.app`; o workflow não inventa nem registra outro identificador.
- Uma **chave de equipe** da API do App Store Connect, com acesso ao aplicativo, a Certificates, Identifiers & Profiles e à assinatura em nuvem. Chaves individuais não acessam os endpoints de Provisioning.
- A permissão de cloud-managed app distribution é padrão para Account Holder/Admin; outros papéis dependem de permissões adicionais. Não assumir que uma chave App Manager isolada basta. O titular deve escolher e verificar o papel; o workflow não concede acesso, solicita API access nem aceita contratos.
- Um profile de desenvolvimento utilizável pela equipe. A geração automática de um profile Apple Development pode exigir um aparelho iOS já registrado, mesmo ao arquivar para um destino genérico. Uma conta nova sem dispositivos pode receber esse erro. O workflow não registra aparelhos, não usa `-allowProvisioningDeviceRegistration` e não inventa UDID.

O dispositivo registrado é necessário para o profile da etapa de archive de desenvolvimento escolhida aqui. TestFlight não exige registrar os UDIDs dos testers.

Chaves TEAM abrangem todos os apps da equipe e não podem ser limitadas só ao ConsegVida. O papel Admin tem alcance amplo. Configure apenas uma chave autorizada para esse uso e proteja o ambiente; não cole material de chave em chat, código, issue ou log.

## Campos mínimos

Criar/configurar manualmente o GitHub Environment **`apple-testflight`** no repositório `Avffc-kaizen/Consegvida`. Restringir o ambiente à branch `main` e usar as proteções de revisão apropriadas à equipe.

| Tipo | Nome | Valor |
|---|---|---|
| Environment variable | `APPLE_TEAM_ID` | Team ID Apple existente, 10 caracteres |
| Environment variable | `ASC_APP_ID` | ID numérico do app record existente no App Store Connect |
| Environment secret | `ASC_KEY_ID` | Key ID da chave TEAM autorizada |
| Environment secret | `ASC_ISSUER_ID` | Issuer ID da equipe, formato UUID |
| Environment secret | `ASC_PRIVATE_KEY_P8` | Conteúdo PEM completo do arquivo `.p8` dessa chave TEAM |

Nenhum ID ou segredo é fornecido por este repositório. P12 não é exigido por esta primeira rota de assinatura automática: o Xcode usa a chave de equipe para autorizar o provisionamento e o cloud signing. Isso não garante que a conta tenha permissões, certificados disponíveis ou quota suficiente; esses requisitos são verificados pela Apple na execução.

## Executar

Na aba Actions, selecionar **ConsegVida iOS TestFlight**, escolher a branch **main** e executar manualmente. O workflow não roda por push ou pull request. Não chama o workflow de testes já aprovados. Usa macOS 26 e Xcode 26.6 e recebe os segredos somente no passo de distribuição.

Antes de compilar, verifica o formato da configuração, a chave EC P-256, o commit selecionado, as opções de exportação do Xcode, o app record, o App ID e a ausência da mesma versão/build no App Store Connect. As verificações Apple usam somente GET. Se uma precondição falhar, não inicia o archive ou o upload.

Após a preparação unsigned, cria um archive Release para `generic/platform=iOS`, com `DEVELOPMENT_TEAM` explícito, `CODE_SIGN_STYLE=Automatic`, `-allowProvisioningUpdates` e autenticação pela chave TEAM. Verifica assinatura Apple Development, Team ID, profile, versão, conteúdo, privacidade e ícones. A distribuição usa `xcodebuild -exportArchive`, método `app-store-connect`, destino `upload` e assinatura automática. `manageAppVersionAndBuildNumber=false` preserva a versão/build dos fontes; números não são incrementados silenciosamente.

O script escreve a chave em arquivo temporário modo `0600`, dentro de diretório `0700`, remove os segredos do ambiente dos subprocessos, usa chaveiro temporário e restaura a configuração anterior no cleanup. Logs sensíveis, profiles, archive assinado, IPA e arquivo `.p8` não são enviados como artifacts. Apenas mensagens de estado e categorias fixas de erro chegam ao log/resumo do workflow. A limpeza é tentada também em interrupções normais; o runner é efêmero.

## Recursos que o Xcode pode provisionar e limites de repetição

**Executar a assinatura automática pode criar ou atualizar um certificado Apple Development e profiles na conta Apple.** O cloud signing também depende dos certificados de distribuição geridos pela Apple e do acesso concedido à equipe. O workflow não revoga certificados/perfis e não gerencia permissões ou quotas.

A chave privada de desenvolvimento criada no chaveiro temporário desaparece no cleanup, mas o certificado correspondente pode continuar registrado na Apple. Repetir o workflow pode acumular certificados e atingir a quota. Antes de várias execuções, o titular pode precisar gerir um certificado de CI estável por um processo protegido próprio. Não existe persistência improvisada de chave nem revogação automática nesta preparação.

Se a versão/build já existir, o script para antes de compilar; não a substitui. Se o upload terminar e o processamento ainda estiver pendente, conferir o App Store Connect antes de executar novamente. Falhas de assinatura, quota, permissão ou ACL do chaveiro produzem uma categoria explícita; não há retentativa automática de assinatura/upload nem alteração manual do binário para contornar erros.

O chaveiro temporário é desbloqueado e selecionado, mas a ACL de uma chave nova criada pelo Xcode pode ainda exigir autorização de uso pelo `codesign` sem interação. Esse comportamento não foi validado com a conta real. Se a assinatura parar por esse motivo, o envio não começa; o titular precisará revisar a identidade/ACL e o processo de CI antes de nova tentativa. Não há promessa de execução completa apenas pelo preenchimento dos cinco campos.

## O que significa sucesso

Sucesso do export indica que o Xcode concluiu o envio. O script consulta brevemente o processamento Apple; `VALID` é informado quando observado. `PROCESSING` pode continuar após o fim do workflow, e `FAILED`/`INVALID` interrompem a execução. Envio não equivale a aprovação da App Store nem a um link público de TestFlight.

Depois, completar as informações de teste/contato e configurar o grupo de testers autorizado no App Store Connect. A primeira disponibilização para testers externos depende de TestFlight App Review. Este workflow não convida pessoas, não cria link público nem envia o aplicativo para App Review da loja.

## Fontes oficiais

- [Cloud signing e autenticação por chave API no xcodebuild](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Xcode 13: assinatura automática em CI/headless com chave API](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-13-release-notes)
- [Pré-requisitos de um profile de desenvolvimento](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile)
- [Chaves TEAM e individuais da API](https://developer.apple.com/documentation/AppStoreConnectAPI/creating-api-keys-for-app-store-connect-api)
- [Papéis e permissão cloud-managed app distribution](https://developer.apple.com/documentation/appstoreconnectapi/userrole)
- [Consultar app record](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_)
- [Consultar bundle IDs](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-bundleids)
- [Consultar builds](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-builds)
- [Upload de builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Testers externos e revisão beta](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)

As opções de `ExportOptions.plist` são conferidas contra `xcodebuild -help` no runner selecionado. Na preparação passaram sintaxe Bash/Python/YAML e 13 verificações locais com ferramentas e respostas simuladas: recusa de configuração/ref inválidos, modo do arquivo temporário, remoção de segredos do ambiente, precondições Apple, duplicidade, ordem das etapas, cleanup, conversão DER/JOSE, ocultação de saída sensível e contrato de export/processamento. Uma 14ª verificação usou uma chave EC P-256 sintética e efêmera para conferir a assinatura ES256 e os claims do JWT com OpenSSL; a chave foi descartada localmente. Nenhuma credencial de conta, chamada Apple, assinatura de aplicativo ou upload foi usado nesses testes; eles não demonstram execução completa na conta.
