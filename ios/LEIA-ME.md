# About Inbox (iOS)

App nativo em SwiftUI + extensão **Compartilhar**: no WhatsApp, a mensagem, o áudio ou a foto vão direto para o About Inbox.

## Rodar no iPhone (5 minutos)

1. Abra **`AboutInbox.xcodeproj`** no Xcode (16 ou mais novo).
2. Clique no projeto **AboutInbox** (ícone azul, no topo da lista à esquerda).
3. Em **TARGETS**, escolha **AboutInbox** → aba **Signing & Capabilities** → **Team**: selecione a sua conta de desenvolvedor.
4. Faça o mesmo no target **ShareExtension** (mesmo Team).
5. Ainda em Signing & Capabilities, confira **App Groups** nos dois targets: o grupo
   `group.com.felipealencar.about.inbox` tem que estar **marcado** nos dois.
   Se aparecer em vermelho, clique no botão de atualizar (↻) ao lado ou desmarque e marque de novo.
6. Conecte o iPhone, escolha ele no topo do Xcode e aperte **▶ Run**.

> **"Bundle identifier já em uso"?** Em **Build Settings** do *projeto*, procure `BUNDLE_PREFIX`
> e troque `com.felipealencar.about` por outro (ex.: `br.com.aboutgroup`). O app, a extensão e o
> App Group mudam juntos.

## Usar

- **WhatsApp → About Inbox:** segure a mensagem → **Encaminhar** → ícone de compartilhar
  (canto inferior direito) → **About Inbox** → **Publicar**. Na primeira vez, se não aparecer,
  role a fileira de apps até o fim → **Mais** → ative o About Inbox.
- Ao abrir o app, a demanda já está lá com o resumo da IA.
- **Áudio encaminhado:** toque em **Transcrever** no anexo.
- **Lembretes** chegam como notificação mesmo com o app fechado.
- **Enviar para About CRM** cria o lead em "Novo lead", com origem WhatsApp e uma anotação com tudo.

## Onde fica cada coisa

| Pasta | O quê |
|---|---|
| `AboutInbox/` | App (telas, gravador, IA, CRM, lembretes) |
| `ShareExtension/` | A extensão do menu Compartilhar |
| `Shared/` | Modelos usados pelos dois (demanda, nota, anexo, pasta compartilhada) |
| `Config/` | Entitlements (App Group) e Info.plist da extensão |

- Os dados ficam **no iPhone**, na pasta do App Group (`demandas.json` + áudios em `midia/`).
- A IA usa a função `inbox-ia` (Supabase). O CRM usa o mesmo banco do About CRM web.
  Os dois endereços podem ser trocados em **Ajustes → Conexões**.
