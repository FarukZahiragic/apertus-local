# Participant chat UI

The participant build keeps llama.cpp's existing chat UI and limits its controls
to the Apertus workshop workflow. The UI is compiled into the native runtime;
participants need no Node.js, UI installation or extra server.

It keeps chat history, streaming, Stop, Markdown, text/PDF attachments, system
messages, and the server's supported sampling controls. Image upload and audio
input appear when the loaded runtime has their encoders. Text-only mode omits
those input choices.

The UI removes generic reasoning-effort menus, unconfigured tool/MCP/agent
controls, JavaScript/symbolic-math tool settings, and video input claims. The
server's existing `THINKING` setting remains available; this does not remove
Apertus's thinking support. A generic effort level is not presented as an
Apertus quality setting.

Saved browser settings are handled without clearing conversations: old reasoning
effort choices defer to the server, old tool choices supply no tools to chat,
and saved MCP servers do not reconnect. Theme, chat history and other supported
preferences remain available. This is a participant UI profile, not an API
authorization boundary.

## Maintainer builds

`patches/0006-apertus-workshop-ui.patch` changes the pinned upstream UI. Source
builds use Node.js 24/npm to compile that UI; Mac source setup installs missing
Node through Homebrew. The native Mac/Linux and Windows build scripts require a
source UI build and disable downloading the generic upstream UI. A failed UI
build stops packaging rather than silently delivering the generic interface.

No model, tokenizer, encoder, inference graph or performance default changes.
The usual prebuilt participant packages contain the compiled UI assets.

`tests/workshop_ui.mjs` runs a real browser against the served build. It checks
desktop/mobile menus, text-only versus multimodal inputs, seeded old preferences,
the actual chat request, and history after reload. Native Linux CI runs it
against the delivered archive with external networking blocked. Other native
builds compile the same UI and retain their real-model checks.
