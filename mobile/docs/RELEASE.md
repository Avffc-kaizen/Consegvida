# Publicação Android e iOS

Data da preparação: 29/10/2026. Este documento prepara a distribuição; não é um comprovante de lançamento.

## Ferramenta do vídeo

Reel de referência: https://www.instagram.com/reel/DfFZHpyD4Ty/

A legenda pública de Fabiano Carvalho identifica **xtool**, CLI open source para desenvolver, assinar e instalar apps iOS em Swift. Fonte oficial: https://github.com/xtool-org/xtool .

Versão usada na preparação: **1.24.0**, publicada em 26/10/2026. A versão oficial Linux foi executada e o comando `new --skip-setup` gerou um projeto real. Isso não instala o Apple SDK nem autentica conta de desenvolvedor.

| Pacote oficial | SHA-256 verificado |
|---|---|
| `xtool-x86_64.AppImage` | `dbfd9d7216f077c84c171b688c4173c37c23ca76bf7fd185d1a9ae8a53dab59f` |
| `xtool.app.zip` | `a56e98d69dea02a97a17e609f0ae8771c57ffaab23f1d62513fd9ada222026b3` |

Release: https://github.com/xtool-org/xtool/releases/tag/1.24.0 .

### Limitação de distribuição confirmada

Em 29/10/2026, os PRs upstream [326](https://github.com/xtool-org/xtool/pull/326) (assinatura de distribuição) e [327](https://github.com/xtool-org/xtool/pull/327) (upload ao App Store Connect) continuavam abertos e não mergeados. O fluxo estável de assinatura usa desenvolvimento. Um `--configuration release --ipa --sign` não comprova uma assinatura de distribuição.

Não usar forks não homologados de assinatura para contornar esta limitação. Preparar o app com xtool e usar o fluxo Apple de archive/export/Store Connect, com a conta legítima do titular. A ferramenta não gera Android; o cliente Android é separado, com o mesmo conteúdo.

## Pré-requisitos de contas

| Plataforma | Necessário | Situação a comprovar |
|---|---|---|
| Apple | Apple Developer Program ativo, App Store Connect, titularidade, Bundle ID, certificados e profiles | Acesso e assinatura ainda não comprovados |
| Google | Play Console verificado, titularidade, identificador disponível e chave de upload | Acesso e assinatura ainda não comprovados |
| Ambas | Política pública de privacidade, contato de suporte, imagens reais e questionários completos | Conteúdo editorial preparado; publicação e titularidade pendentes |

Nenhum pagamento ou criação de credencial foi realizado nesta preparação. Não guardar passwords, `.p8`, `.p12`, profiles ou keystores no Git. A autenticação deve ocorrer no painel oficial ou mecanismo seguro, nunca por valores enviados em chat.

Custos oficiais consultados: Apple Developer **US$ 99/ano**; Google Play **US$ 25 uma vez**. Cobrança local, tributos e condição das contas existentes devem ser conferidos no cadastro. Fontes: https://developer.apple.com/help/account/membership/program-enrollment e https://support.google.com/googleplay/android-developer/answer/6112435 .

Contas pessoais Google Play criadas após 13/11/2023 exigem pelo menos 12 participantes inscritos continuamente durante 14 dias de teste fechado antes da solicitação de acesso à produção. A regra depende do tipo/data da conta; não é prazo universal. Fonte: https://support.google.com/googleplay/android-developer/answer/14151465 .

## Android

O projeto usa API 36, minSdk 26, Java 17, AGP 8.13.2 e Gradle 8.13. Requer JDK completo e SDK Android; o wrapper verifica o checksum da distribuição.

```sh
cd mobile/android
./gradlew --no-daemon :app:assembleDebug :app:lintDebug
```

O APK `app/build/outputs/apk/debug/app-debug.apk` é para teste direto. Sua assinatura debug não é identidade definitiva de produção.

Para produção, conferir identificador antes do primeiro lançamento, configurar chave de upload fora do código, ativar/confirmar Play App Signing no console e gerar AAB assinado. O `bundleRelease` sem configuração de assinatura não resolve essa etapa. Enviar primeiro a testes internos, executar o roteiro de homologação e completar o caminho de revisão aplicável à conta.

Requisitos Android: https://support.google.com/googleplay/android-developer/answer/11926878 .

## iOS com xtool

Em macOS com Xcode configurado, instalar a release oficial ou o tap oficial documentado em https://xtool.sh/documentation/xtool/installation-macos/ . Em Linux/WSL, usar Swift compatível e SDK extraído de um Xcode obtido legitimamente: https://xtool.sh/documentation/xtool/installation-linux/ .

```sh
cd mobile/ios
xtool --version
xtool dev build --triple arm64-apple-ios-simulator
```

O último comando é para macOS ARM e SDK de simulador. O script `ci-simulator.sh` escolhe ARM/x86_64 conforme o host e verifica a instalação/abertura no simulador, sem autenticação Apple.

Para testar em iPhone físico, são necessários SDK, aparelho pareado e autenticação de desenvolvedor configurada com segurança. Só então executar `xtool dev`. Conta gratuita pode ter limitações de provisionamento e não autoriza distribuição na App Store.

Para distribuição, `xtool dev generate-xcode-project` prepara um projeto Xcode. Conferir a geração, Team, Bundle ID, capabilities, ícones e privacy manifest; arquivar com Xcode, validar distribuição e enviar ao App Store Connect/TestFlight. Escolher build, ficha, classificação, privacidade e países antes da submissão à App Review. Upload/TestFlight não equivale a publicação na loja.

Requisitos Apple: https://developer.apple.com/news/upcoming-requirements/ . Diretrizes: https://developer.apple.com/app-store/review/guidelines/ .

## Homologação antes da loja

1. Instalação limpa em Android e iPhone reais, com tamanhos de texto padrão e ampliado.
2. Escolher/iniciar/concluir uma missão; confirmar exatamente um registro.
3. Reabrir o app e verificar persistência; repetir conclusão no mesmo dia sem duplicar.
4. Retomar em novo dia, alterar fuso para testar preservação do histórico e verificar dia local.
5. Cancelar exclusão preserva histórico; confirmar exclusão remove histórico e missão ativa.
6. Simular arquivo inválido e falta de escrita em ambiente de teste: recuperação visível, sem falso sucesso ou apagamento silencioso.
7. Confirmar funcionamento offline, ausência de tráfego de app e permissões, exclusão de backups e abertura externa do manifesto somente por ação do usuário.
8. Capturar screenshots reais, preencher privacidade com o binário final e revisar metadados.
9. Submeter; registrar build, recibos, status de revisão e URLs finais de loja.

## Custo e manutenção

O fluxo principal não depende de servidor nem API de IA. Esta versão não cria cobrança por atendimento, token ou usuário ativo. São duas interfaces nativas com conteúdo compartilhado; o custo de manutenção inclui validar ambas após alterações. Runners standard em repositório público têm computação gratuita segundo o GitHub; artefatos têm franquia de armazenamento separada, por isso retenção de um dia. Não foi adquirido serviço pago de build.

Fonte GitHub: https://docs.github.com/en/billing/concepts/product-billing/github-actions .
