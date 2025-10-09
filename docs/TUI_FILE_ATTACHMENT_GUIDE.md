# TUI File Attachment Guide

Complete guide on how the OpenCode TUI attaches files and images to session prompts.

## Overview

The TUI uses a multi-stage pipeline to attach files to prompts:

1. **Attachment Creation** - Create attachment objects from files/images
2. **Textarea Integration** - Insert attachments into the textarea
3. **Prompt Building** - Extract attachments when submitting
4. **Message Conversion** - Convert to OpenCode message parts
5. **API Serialization** - Convert to API parameters
6. **Session Prompt** - Send via `Session.Prompt()` API

---

## 1. Attachment Types

### Type: `file` (Text Files)

Regular text files are referenced by filesystem path.

**Structure:**

```go
&attachment.Attachment{
    ID:        "uuid-here",
    Type:      "file",
    Display:   "@src/main.go",           // How it appears in the input
    URL:       "file:///absolute/path/to/src/main.go",
    Filename:  "src/main.go",
    MediaType: "text/plain",
    Source: &attachment.FileSource{
        Path: "/absolute/path/to/src/main.go",
        Mime: "text/plain",
    },
}
```

**Implementation:** [`packages/tui/internal/components/chat/editor.go:838-851`](packages/tui/internal/components/chat/editor.go#L838-L851)

```go
// For text files, create a simple file reference
if mediaType == "text/plain" {
    return &attachment.Attachment{
        ID:        uuid.NewString(),
        Type:      "file",
        Display:   "@" + filePath,
        URL:       fmt.Sprintf("file://%s", absolutePath),
        Filename:  filePath,
        MediaType: mediaType,
        Source: &attachment.FileSource{
            Path: absolutePath,
            Mime: mediaType,
        },
    }
}
```

### Type: `file` (Images/Binary)

Images and binary files are embedded as base64 data URLs.

**Structure:**

```go
&attachment.Attachment{
    ID:        "uuid-here",
    Type:      "file",
    Display:   "[Image #1]",             // Visual placeholder
    URL:       "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    Filename:  "screenshot.png",
    MediaType: "image/png",
    Source: &attachment.FileSource{
        Path: "/absolute/path/to/screenshot.png",
        Mime: "image/png",
        Data: []byte{...},               // Raw image bytes
    },
}
```

**Implementation:** [`packages/tui/internal/components/chat/editor.go:854-881`](packages/tui/internal/components/chat/editor.go#L854-L881)

```go
// For binary files (images, PDFs), read and encode
fileBytes, err := os.ReadFile(filePath)
if err != nil {
    slog.Error("Failed to read file", "error", err)
    return nil
}

base64EncodedFile := base64.StdEncoding.EncodeToString(fileBytes)
url := fmt.Sprintf("data:%s;base64,%s", mediaType, base64EncodedFile)
attachmentCount := len(m.textarea.GetAttachments())
attachmentIndex := attachmentCount + 1
label := "File"
if strings.HasPrefix(mediaType, "image/") {
    label = "Image"
}
return &attachment.Attachment{
    ID:        uuid.NewString(),
    Type:      "file",
    MediaType: mediaType,
    Display:   fmt.Sprintf("[%s #%d]", label, attachmentIndex),
    URL:       url,
    Filename:  filePath,
    Source: &attachment.FileSource{
        Path: absolutePath,
        Mime: mediaType,
        Data: fileBytes,
    },
}
```

### Type: `symbol`

Code symbols (functions, classes, etc.) with location information.

**Structure:**

```go
&attachment.Attachment{
    ID:        "uuid-here",
    Type:      "symbol",
    Display:   "@handleRequest",
    URL:       "src/server.go:42:0",
    Filename:  "handleRequest",
    MediaType: "text/plain",
    Source: &attachment.SymbolSource{
        Path:  "/absolute/path/to/src/server.go",
        Name:  "main.handleRequest",
        Kind:  12,  // Function
        Range: attachment.SymbolRange{
            Start: attachment.Position{Line: 42, Char: 0},
            End:   attachment.Position{Line: 58, Char: 1},
        },
    },
}
```

**Implementation:** [`packages/tui/internal/components/chat/editor.go:271-297`](packages/tui/internal/components/chat/editor.go#L271-L297)

```go
symbol := msg.Item.RawData.(opencode.Symbol)
parts := strings.Split(symbol.Name, ".")
lastPart := parts[len(parts)-1]
attachment := &attachment.Attachment{
    ID:        uuid.NewString(),
    Type:      "symbol",
    Display:   "@" + lastPart,
    URL:       msg.Item.Value,
    Filename:  lastPart,
    MediaType: "text/plain",
    Source: &attachment.SymbolSource{
        Path: symbol.Location.Uri,
        Name: symbol.Name,
        Kind: int(symbol.Kind),
        Range: attachment.SymbolRange{
            Start: attachment.Position{
                Line: int(symbol.Location.Range.Start.Line),
                Char: int(symbol.Location.Range.Start.Character),
            },
            End: attachment.Position{
                Line: int(symbol.Location.Range.End.Line),
                Char: int(symbol.Location.Range.End.Character),
            },
        },
    },
}
```

### Type: `text`

Long pasted text snippets embedded inline.

**Structure:**

```go
&attachment.Attachment{
    ID:        "uuid-here",
    Type:      "text",
    Display:   "[pasted #1 150+ lines]",
    URL:       "data:text/plain;base64,VGhpcyBpcyBhIGxvbmcgdGV4dC4uLg==",
    Filename:  "pasted-text-1.txt",
    MediaType: "text/plain",
    Source: &attachment.TextSource{
        Value: "This is a long text...",
    },
}
```

**Implementation:** [`packages/tui/internal/components/chat/editor.go:685-714`](packages/tui/internal/components/chat/editor.go#L685-L714)

```go
func (m *editorComponent) handleLongPaste(text string) {
    lines := strings.Split(text, "\n")
    lineCount := len(lines)
    m.pasteCounter++

    fileBytes := []byte(text)
    base64EncodedText := base64.StdEncoding.EncodeToString(fileBytes)
    url := fmt.Sprintf("data:text/plain;base64,%s", base64EncodedText)

    fileName := fmt.Sprintf("pasted-text-%d.txt", m.pasteCounter)
    displayText := fmt.Sprintf("[pasted #%d %d+ lines]", m.pasteCounter, lineCount)

    attachment := &attachment.Attachment{
        ID:        uuid.NewString(),
        Type:      "text",
        MediaType: "text/plain",
        Display:   displayText,
        URL:       url,
        Filename:  fileName,
        Source: &attachment.TextSource{
            Value: text,
        },
    }

    m.textarea.InsertAttachment(attachment)
    m.textarea.InsertString(" ")
}
```

### Type: `agent`

Agent references for multi-agent conversations.

**Structure:**

```go
&attachment.Attachment{
    ID:      "uuid-here",
    Type:    "agent",
    Display: "@code-reviewer",
    Source: &attachment.AgentSource{
        Name: "code-reviewer",
    },
}
```

**Implementation:** [`packages/tui/internal/components/chat/editor.go:311-322`](packages/tui/internal/components/chat/editor.go#L311-L322)

```go
name := msg.Item.Value
attachment := &attachment.Attachment{
    ID:      uuid.NewString(),
    Type:    "agent",
    Display: "@" + name,
    Source: &attachment.AgentSource{
        Name: name,
    },
}
```

---

## 2. Creating Attachments

### From File Path

**Code:** [`packages/tui/internal/components/chat/editor.go:884-903`](packages/tui/internal/components/chat/editor.go#L884-L903)

```go
func (m *editorComponent) createAttachmentFromPath(filePath string) *attachment.Attachment {
    extension := filepath.Ext(filePath)
    mediaType := getMediaTypeFromExtension(extension)
    absolutePath := filePath
    if !filepath.IsAbs(filePath) {
        absolutePath = filepath.Join(util.CwdPath, filePath)
    }
    return &attachment.Attachment{
        ID:        uuid.NewString(),
        Type:      "file",
        Display:   "@" + filePath,
        URL:       fmt.Sprintf("file://%s", absolutePath),
        Filename:  filePath,
        MediaType: mediaType,
        Source: &attachment.FileSource{
            Path: absolutePath,
            Mime: mediaType,
        },
    }
}
```

### From Clipboard Image

**Code:** [`packages/tui/internal/components/chat/editor.go:559-581`](packages/tui/internal/components/chat/editor.go#L559-L581)

```go
func (m *editorComponent) Paste() (tea.Model, tea.Cmd) {
    imageBytes := clipboard.Read(clipboard.FmtImage)
    if imageBytes != nil {
        attachmentCount := len(m.textarea.GetAttachments())
        attachmentIndex := attachmentCount + 1
        base64EncodedFile := base64.StdEncoding.EncodeToString(imageBytes)
        attachment := &attachment.Attachment{
            ID:        uuid.NewString(),
            Type:      "file",
            MediaType: "image/png",
            Display:   fmt.Sprintf("[Image #%d]", attachmentIndex),
            Filename:  fmt.Sprintf("image-%d.png", attachmentIndex),
            URL:       fmt.Sprintf("data:image/png;base64,%s", base64EncodedFile),
            Source: &attachment.FileSource{
                Path: fmt.Sprintf("image-%d.png", attachmentIndex),
                Mime: "image/png",
                Data: imageBytes,
            },
        }
        m.textarea.InsertAttachment(attachment)
        m.textarea.InsertString(" ")
        return m, nil
    }
    // ... handle text paste
}
```

### MIME Type Detection

**Code:** [`packages/tui/internal/components/chat/editor.go:817-828`](packages/tui/internal/components/chat/editor.go#L817-L828)

```go
func getMediaTypeFromExtension(ext string) string {
    switch strings.ToLower(ext) {
    case ".jpg":
        return "image/jpeg"
    case ".png", ".jpeg", ".gif", ".webp":
        return "image/" + ext[1:]
    case ".pdf":
        return "application/pdf"
    default:
        return "text/plain"
    }
}
```

---

## 3. Inserting into Textarea

**Code:** [`packages/tui/internal/components/textarea/textarea.go:656-671`](packages/tui/internal/components/textarea/textarea.go#L656-L671)

```go
// InsertAttachment inserts an attachment at the cursor position.
func (m *Model) InsertAttachment(att *attachment.Attachment) {
    if m.CharLimit > 0 {
        availSpace := m.CharLimit - m.Length()
        if availSpace <= 0 {
            return
        }
    }

    // Insert the attachment at the current cursor position
    m.value[m.row] = append(
        m.value[m.row][:m.col],
        append([]any{att}, m.value[m.row][m.col:]...)...)
    m.col++
    m.SetCursorColumn(m.col)
}
```

The textarea stores attachments as special elements in its internal structure, rendering them with custom styling while preserving their position in the text.

---

## 4. Extracting Attachments

When submitting, extract all attachments with their positions:

**Code:** [`packages/tui/internal/components/textarea/textarea.go:733-764`](packages/tui/internal/components/textarea/textarea.go#L733-L764)

```go
// GetAttachments returns all attachments in the textarea with accurate position indices.
func (m Model) GetAttachments() []*attachment.Attachment {
    var attachments []*attachment.Attachment
    position := 0 // Track absolute position in the text

    for rowIdx, row := range m.value {
        colPosition := 0 // Track position within the current row

        for _, item := range row {
            switch v := item.(type) {
            case *attachment.Attachment:
                // Clone the attachment to avoid modifying the original
                att := *v
                att.StartIndex = position + colPosition
                att.EndIndex = position + colPosition + len(v.Display)
                attachments = append(attachments, &att)
                colPosition += len(v.Display)
            case rune:
                colPosition++
            }
        }

        // Add newline character position (except for last row)
        if rowIdx < len(m.value)-1 {
            position += colPosition + 1 // +1 for newline
        } else {
            position += colPosition
        }
    }

    return attachments
}
```

**Usage:** [`packages/tui/internal/components/chat/editor.go:527-530`](packages/tui/internal/components/chat/editor.go#L527-L530)

```go
attachments := m.textarea.GetAttachments()

prompt := app.Prompt{Text: value, Attachments: attachments}
m.app.State.AddPromptToHistory(prompt)
```

---

## 5. Converting to Message Parts

### Prompt → Message

**Code:** [`packages/tui/internal/app/prompt.go:17-130`](packages/tui/internal/app/prompt.go#L17-L130)

```go
func (p Prompt) ToMessage(messageID string, sessionID string) Message {
    message := opencode.UserMessage{
        ID:        messageID,
        SessionID: sessionID,
        Role:      opencode.UserMessageRoleUser,
        Time: opencode.UserMessageTime{
            Created: float64(time.Now().UnixMilli()),
        },
    }

    // Start with text part
    parts := []opencode.PartUnion{opencode.TextPart{
        ID:        id.Ascending(id.Part),
        MessageID: messageID,
        SessionID: sessionID,
        Type:      opencode.TextPartTypeText,
        Text:      p.Text,
    }}

    // Add file/symbol parts
    for _, attachment := range p.Attachments {
        if attachment.Type == "text" {
            continue // Text attachments merged into text part
        }

        text := opencode.FilePartSourceText{
            Start: int64(attachment.StartIndex),
            End:   int64(attachment.EndIndex),
            Value: attachment.Display,
        }

        source := &opencode.FilePartSource{}
        switch attachment.Type {
        case "file":
            if fileSource, ok := attachment.GetFileSource(); ok {
                source = &opencode.FilePartSource{
                    Text: text,
                    Path: fileSource.Path,
                    Type: opencode.FilePartSourceTypeFile,
                }
            }
        case "symbol":
            if symbolSource, ok := attachment.GetSymbolSource(); ok {
                source = &opencode.FilePartSource{
                    Text: text,
                    Path: symbolSource.Path,
                    Type: opencode.FilePartSourceTypeSymbol,
                    Kind: int64(symbolSource.Kind),
                    Name: symbolSource.Name,
                    Range: opencode.SymbolSourceRange{
                        Start: opencode.SymbolSourceRangeStart{
                            Line:      float64(symbolSource.Range.Start.Line),
                            Character: float64(symbolSource.Range.Start.Char),
                        },
                        End: opencode.SymbolSourceRangeEnd{
                            Line:      float64(symbolSource.Range.End.Line),
                            Character: float64(symbolSource.Range.End.Char),
                        },
                    },
                }
            }
        }

        parts = append(parts, opencode.FilePart{
            ID:        id.Ascending(id.Part),
            MessageID: messageID,
            SessionID: sessionID,
            Type:      opencode.FilePartTypeFile,
            Filename:  attachment.Filename,
            Mime:      attachment.MediaType,
            URL:       attachment.URL,
            Source:    *source,
        })
    }

    return Message{
        Info:  message,
        Parts: parts,
    }
}
```

### Message → API Parameters

**Code:** [`packages/tui/internal/app/prompt.go:210-283`](packages/tui/internal/app/prompt.go#L210-L283)

```go
func (m Message) ToSessionChatParams() []opencode.SessionPromptParamsPartUnion {
    parts := []opencode.SessionPromptParamsPartUnion{}
    for _, part := range m.Parts {
        switch p := part.(type) {
        case opencode.TextPart:
            parts = append(parts, opencode.TextPartInputParam{
                ID:        opencode.F(p.ID),
                Type:      opencode.F(opencode.TextPartInputTypeText),
                Text:      opencode.F(p.Text),
                Synthetic: opencode.F(p.Synthetic),
                Time: opencode.F(opencode.TextPartInputTimeParam{
                    Start: opencode.F(p.Time.Start),
                    End:   opencode.F(p.Time.End),
                }),
            })
        case opencode.FilePart:
            var source opencode.FilePartSourceUnionParam
            switch p.Source.Type {
            case "file":
                source = opencode.FileSourceParam{
                    Type: opencode.F(opencode.FileSourceTypeFile),
                    Path: opencode.F(p.Source.Path),
                    Text: opencode.F(opencode.FilePartSourceTextParam{
                        Start: opencode.F(int64(p.Source.Text.Start)),
                        End:   opencode.F(int64(p.Source.Text.End)),
                        Value: opencode.F(p.Source.Text.Value),
                    }),
                }
            case "symbol":
                source = opencode.SymbolSourceParam{
                    Type: opencode.F(opencode.SymbolSourceTypeSymbol),
                    Path: opencode.F(p.Source.Path),
                    Name: opencode.F(p.Source.Name),
                    Kind: opencode.F(p.Source.Kind),
                    Range: opencode.F(opencode.SymbolSourceRangeParam{
                        Start: opencode.F(opencode.SymbolSourceRangeStartParam{
                            Line:      opencode.F(float64(p.Source.Range.(opencode.SymbolSourceRange).Start.Line)),
                            Character: opencode.F(float64(p.Source.Range.(opencode.SymbolSourceRange).Start.Character)),
                        }),
                        End: opencode.F(opencode.SymbolSourceRangeEndParam{
                            Line:      opencode.F(float64(p.Source.Range.(opencode.SymbolSourceRange).End.Line)),
                            Character: opencode.F(float64(p.Source.Range.(opencode.SymbolSourceRange).End.Character)),
                        }),
                    }),
                    Text: opencode.F(opencode.FilePartSourceTextParam{
                        Value: opencode.F(p.Source.Text.Value),
                        Start: opencode.F(p.Source.Text.Start),
                        End:   opencode.F(p.Source.Text.End),
                    }),
                }
            }
            parts = append(parts, opencode.FilePartInputParam{
                ID:       opencode.F(p.ID),
                Type:     opencode.F(opencode.FilePartInputTypeFile),
                Mime:     opencode.F(p.Mime),
                URL:      opencode.F(p.URL),
                Filename: opencode.F(p.Filename),
                Source:   opencode.F(source),
            })
        case opencode.AgentPart:
            parts = append(parts, opencode.AgentPartInputParam{
                ID:   opencode.F(p.ID),
                Type: opencode.F(opencode.AgentPartInputTypeAgent),
                Name: opencode.F(p.Name),
                Source: opencode.F(opencode.AgentPartInputSourceParam{
                    Value: opencode.F(p.Source.Value),
                    Start: opencode.F(p.Source.Start),
                    End:   opencode.F(p.Source.End),
                }),
            })
        }
    }
    return parts
}
```

---

## 6. Sending via Session.Prompt()

**Code:** [`packages/tui/internal/app/app.go:783-820`](packages/tui/internal/app/app.go#L783-L820)

```go
func (a *App) SendPrompt(ctx context.Context, prompt Prompt) (*App, tea.Cmd) {
    var cmds []tea.Cmd
    if a.Session.ID == "" {
        session, err := a.CreateSession(ctx)
        if err != nil {
            return a, toast.NewErrorToast(err.Error())
        }
        a.Session = session
        cmds = append(cmds, util.CmdHandler(SessionCreatedMsg{Session: session}))
    }

    messageID := id.Ascending(id.Message)
    message := prompt.ToMessage(messageID, a.Session.ID)

    a.Messages = append(a.Messages, message)

    cmds = append(cmds, func() tea.Msg {
        _, err := a.Client.Session.Prompt(ctx, a.Session.ID, opencode.SessionPromptParams{
            Model: opencode.F(opencode.SessionPromptParamsModel{
                ProviderID: opencode.F(a.Provider.ID),
                ModelID:    opencode.F(a.Model.ID),
            }),
            Agent:     opencode.F(a.Agent().Name),
            MessageID: opencode.F(messageID),
            Parts:     opencode.F(message.ToSessionChatParams()),
        })
        if err != nil {
            errormsg := fmt.Sprintf("failed to send message: %v", err)
            slog.Error(errormsg)
            return toast.NewErrorToast(errormsg)()
        }
        return nil
    })

    return a, tea.Batch(cmds...)
}
```

---

## Complete Example Flow

### Scenario: User types `@main.go How does this work?` with a pasted screenshot

**Step 1: Create file attachment from completion**

```go
// User selects main.go from @ completions
attachment := &attachment.Attachment{
    ID:        "att-001",
    Type:      "file",
    Display:   "@main.go",
    URL:       "file:///home/user/project/main.go",
    Filename:  "main.go",
    MediaType: "text/plain",
    Source: &attachment.FileSource{
        Path: "/home/user/project/main.go",
        Mime: "text/plain",
    },
}
m.textarea.InsertAttachment(attachment)
```

**Step 2: Create image attachment from paste**

```go
// User pastes screenshot (Ctrl+V)
imageBytes := clipboard.Read(clipboard.FmtImage)
attachment := &attachment.Attachment{
    ID:        "att-002",
    Type:      "file",
    Display:   "[Image #1]",
    URL:       "data:image/png;base64,iVBORw0KGgo...",
    Filename:  "image-1.png",
    MediaType: "image/png",
    Source: &attachment.FileSource{
        Path: "image-1.png",
        Mime: "image/png",
        Data: imageBytes,
    },
}
m.textarea.InsertAttachment(attachment)
```

**Step 3: Extract attachments on submit**

```go
// User presses Enter
value := "@main.go [Image #1] How does this work?"
attachments := m.textarea.GetAttachments()
// Returns:
// [
//   {Display: "@main.go", StartIndex: 0, EndIndex: 8, ...},
//   {Display: "[Image #1]", StartIndex: 9, EndIndex: 19, ...}
// ]
```

**Step 4: Build prompt**

```go
prompt := app.Prompt{
    Text: "@main.go [Image #1] How does this work?",
    Attachments: attachments,
}
```

**Step 5: Convert to message parts**

```go
message := prompt.ToMessage("msg-001", "sess-001")
// message.Parts contains:
// - TextPart{Text: "@main.go [Image #1] How does this work?"}
// - FilePart{
//     Filename: "main.go",
//     URL: "file:///home/user/project/main.go",
//     Source: {Type: "file", Path: "/home/user/project/main.go", ...}
//   }
// - FilePart{
//     Filename: "image-1.png",
//     URL: "data:image/png;base64,...",
//     Source: {Type: "file", Path: "image-1.png", ...}
//   }
```

**Step 6: Send to API**

```go
client.Session.Prompt(ctx, "sess-001", opencode.SessionPromptParams{
    Model: opencode.F(opencode.SessionPromptParamsModel{
        ProviderID: "anthropic",
        ModelID:    "claude-3-5-sonnet-20241022",
    }),
    Agent:     "build",
    MessageID: "msg-001",
    Parts: []opencode.SessionPromptParamsPartUnion{
        opencode.TextPartInputParam{
            Type: "text",
            Text: "@main.go [Image #1] How does this work?",
            ...
        },
        opencode.FilePartInputParam{
            Type:     "file",
            Filename: "main.go",
            Mime:     "text/plain",
            URL:      "file:///home/user/project/main.go",
            Source: opencode.FileSourceParam{
                Type: "file",
                Path: "/home/user/project/main.go",
                Text: {Start: 0, End: 8, Value: "@main.go"},
            },
        },
        opencode.FilePartInputParam{
            Type:     "file",
            Filename: "image-1.png",
            Mime:     "image/png",
            URL:      "data:image/png;base64,iVBORw0KGgo...",
            Source: opencode.FileSourceParam{
                Type: "file",
                Path: "image-1.png",
                Text: {Start: 9, End: 19, Value: "[Image #1]"},
            },
        },
    },
})
```

---

## Key Data Structures

### Attachment Source Types

**File:** [`packages/tui/internal/attachment/attachment.go:11-15`](packages/tui/internal/attachment/attachment.go#L11-L15)

```go
type FileSource struct {
    Path string `toml:"path"`
    Mime string `toml:"mime"`
    Data []byte `toml:"data,omitempty"` // Optional for image data
}
```

**Symbol:** [`packages/tui/internal/attachment/attachment.go:17-22`](packages/tui/internal/attachment/attachment.go#L17-L22)

```go
type SymbolSource struct {
    Path  string      `toml:"path"`
    Name  string      `toml:"name"`
    Kind  int         `toml:"kind"`
    Range SymbolRange `toml:"range"`
}
```

**Text:** [`packages/tui/internal/attachment/attachment.go:7-9`](packages/tui/internal/attachment/attachment.go#L7-L9)

```go
type TextSource struct {
    Value string `toml:"value"`
}
```

**Agent:** [`packages/tui/internal/attachment/attachment.go:29-31`](packages/tui/internal/attachment/attachment.go#L29-L31)

```go
type AgentSource struct {
    Name string `toml:"name"`
}
```

### SDK Types

**FilePartInputParam:** [`packages/sdk/go/session.go:696-703`](packages/sdk/go/session.go#L696-L703)

```go
type FilePartInputParam struct {
    Mime     param.Field[string]                   `json:"mime,required"`
    Type     param.Field[FilePartInputType]        `json:"type,required"`
    URL      param.Field[string]                   `json:"url,required"`
    ID       param.Field[string]                   `json:"id"`
    Filename param.Field[string]                   `json:"filename"`
    Source   param.Field[FilePartSourceUnionParam] `json:"source"`
}
```

**FileSourceParam:** [`packages/sdk/go/session.go:900-904`](packages/sdk/go/session.go#L900-L904)

```go
type FileSourceParam struct {
    Path param.Field[string]                  `json:"path,required"`
    Text param.Field[FilePartSourceTextParam] `json:"text,required"`
    Type param.Field[FileSourceType]          `json:"type,required"`
}
```

---

## Summary

The TUI implements a sophisticated file attachment system that:

1. **Supports multiple formats**: Text files, images, PDFs, code symbols, long text, and agents
2. **Smart encoding**: Text files use path references; binary files use data URLs
3. **Position tracking**: Maintains attachment positions in the prompt text
4. **Type safety**: Uses strongly-typed structures throughout the pipeline
5. **Flexible display**: Shows `@filename` for files, `[Image #N]` for images, etc.

The backend receives fully-qualified file attachments with all necessary metadata to access file contents either via filesystem path or embedded data.
