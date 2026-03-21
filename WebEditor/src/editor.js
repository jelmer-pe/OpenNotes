import { Editor, Extension, InputRule, Node, mergeAttributes } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import TaskList from '@tiptap/extension-task-list'
import TaskItem from '@tiptap/extension-task-item'
import Link from '@tiptap/extension-link'
import Image from '@tiptap/extension-image'
import Placeholder from '@tiptap/extension-placeholder'
import { Markdown } from 'tiptap-markdown'
import { TextSelection, EditorState } from '@tiptap/pm/state'

// Custom Image extension with NodeView for thumbnail, hover UI, delete, popup
const CustomImage = Image.extend({
  addNodeView() {
    return ({ node, editor, getPos }) => {
      const wrapper = document.createElement('div')
      wrapper.className = 'img-wrap'

      const img = document.createElement('img')
      img.src = node.attrs.src
      if (node.attrs.alt) img.alt = node.attrs.alt
      if (node.attrs.title) img.title = node.attrs.title

      // Action buttons container
      const actions = document.createElement('div')
      actions.className = 'img-actions'

      // Delete button
      const del = document.createElement('div')
      del.className = 'img-btn'
      del.innerHTML = '<svg width="10" height="10" viewBox="0 0 10 10"><line x1="2" y1="2" x2="8" y2="8" stroke="white" stroke-width="1.5" stroke-linecap="round"/><line x1="8" y1="2" x2="2" y2="8" stroke="white" stroke-width="1.5" stroke-linecap="round"/></svg>'
      del.addEventListener('mousedown', (e) => {
        e.preventDefault()
        e.stopPropagation()
        const pos = getPos()
        editor.chain().focus().deleteRange({ from: pos, to: pos + node.nodeSize }).run()
      })

      // Copy to clipboard button
      const copy = document.createElement('div')
      copy.className = 'img-btn'
      copy.innerHTML = '<svg width="10" height="10" viewBox="0 0 16 16" fill="none"><rect x="5" y="5" width="9" height="9" rx="1.5" stroke="white" stroke-width="1.5"/><path d="M11 5V3.5A1.5 1.5 0 009.5 2h-6A1.5 1.5 0 002 3.5v6A1.5 1.5 0 003.5 11H5" stroke="white" stroke-width="1.5"/></svg>'
      copy.addEventListener('mousedown', (e) => {
        e.preventDefault()
        e.stopPropagation()
        window.webkit?.messageHandlers?.bridge?.postMessage(
          JSON.stringify({ type: 'copyImage', src: node.attrs.src })
        )
      })

      // Save to downloads button
      const save = document.createElement('div')
      save.className = 'img-btn'
      save.innerHTML = '<svg width="10" height="10" viewBox="0 0 16 16" fill="none"><path d="M8 2v8M8 10l-3-3M8 10l3-3" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/><path d="M2 12v1.5A1.5 1.5 0 003.5 15h9a1.5 1.5 0 001.5-1.5V12" stroke="white" stroke-width="1.5" stroke-linecap="round"/></svg>'
      save.addEventListener('mousedown', (e) => {
        e.preventDefault()
        e.stopPropagation()
        window.webkit?.messageHandlers?.bridge?.postMessage(
          JSON.stringify({ type: 'saveImage', src: node.attrs.src })
        )
      })

      // Metadata label
      const meta = document.createElement('div')
      meta.className = 'img-meta'
      const updateMeta = () => {
        const w = img.naturalWidth
        const h = img.naturalHeight
        if (w && h) {
          fetch(img.src, { method: 'HEAD' })
            .then(r => {
              const bytes = parseInt(r.headers.get('content-length') || '0')
              let size = ''
              if (bytes > 1048576) size = (bytes / 1048576).toFixed(1) + ' MB'
              else if (bytes > 0) size = Math.round(bytes / 1024) + ' KB'
              meta.textContent = `${w}×${h}` + (size ? ` · ${size}` : '')
            })
            .catch(() => { meta.textContent = `${w}×${h}` })
        }
      }
      if (img.complete && img.naturalWidth) updateMeta()
      else img.addEventListener('load', updateMeta)

      // Click to open popup
      img.addEventListener('click', (e) => {
        e.preventDefault()
        e.stopPropagation()
        openImagePopup(img.src)
      })

      actions.appendChild(del)
      actions.appendChild(copy)
      actions.appendChild(save)

      wrapper.appendChild(img)
      wrapper.appendChild(actions)
      wrapper.appendChild(meta)

      return {
        dom: wrapper,
        update(updatedNode) {
          if (updatedNode.type.name !== 'image') return false
          img.src = updatedNode.attrs.src
          return true
        },
        destroy() {},
      }
    }
  },
})

let editor = null

// Custom input rule: typing "[] " creates an unchecked task item
const TaskListInputRule = Extension.create({
  name: 'taskListInputRule',

  addInputRules() {
    return [
      new InputRule({
        find: /^\[\]\s$/,
        handler: ({ state, range, chain }) => {
          chain()
            .deleteRange(range)
            .toggleTaskList()
            .run()
        },
      }),
      // > or " + space creates blockquote
      new InputRule({
        find: /^>\s$/,
        handler: ({ state, range, chain }) => {
          chain()
            .deleteRange(range)
            .toggleBlockquote()
            .run()
        },
      }),
      new InputRule({
        find: /^"\s$/,
        handler: ({ state, range, chain }) => {
          chain()
            .deleteRange(range)
            .toggleBlockquote()
            .run()
        },
      }),
      new InputRule({
        find: /^\[x\]\s$/,
        handler: ({ state, range, chain }) => {
          chain()
            .deleteRange(range)
            .toggleTaskList()
            .command(({ tr, state }) => {
              const { $from } = state.selection
              let depth = $from.depth
              while (depth > 0) {
                const node = $from.node(depth)
                if (node.type.name === 'taskItem') {
                  tr.setNodeAttribute($from.before(depth), 'checked', true)
                  return true
                }
                depth--
              }
              return false
            })
            .run()
        },
      }),
    ]
  },
})

// Custom extension for extra keyboard shortcuts
const ExtraShortcuts = Extension.create({
  name: 'extraShortcuts',

  addKeyboardShortcuts() {
    return {
      // Cmd+E toggles inline code
      'Mod-e': ({ editor }) => {
        editor.chain().focus().toggleCode().run()
        return true
      },

      // Cmd+L toggles link
      'Mod-l': ({ editor }) => {
        if (editor.isActive('link')) {
          editor.chain().focus().unsetLink().run()
        } else {
          showLinkInput()
        }
        return true
      },

      // Cmd+Shift+B toggles blockquote
      'Mod-Shift-b': ({ editor }) => {
        editor.chain().focus().toggleBlockquote().run()
        return true
      },

      // Cmd+Shift+7 toggles bullet list
      'Mod-Shift-7': ({ editor }) => {
        editor.chain().focus().toggleBulletList().run()
        return true
      },

      // Cmd+Shift+8 toggles ordered list
      'Mod-Shift-8': ({ editor }) => {
        editor.chain().focus().toggleOrderedList().run()
        return true
      },

      // Cmd+Shift+S toggles strikethrough
      'Mod-Shift-s': ({ editor }) => {
        editor.chain().focus().toggleStrike().run()
        return true
      },

      // Cmd+Shift+Enter toggles task list
      'Mod-Shift-Enter': ({ editor }) => {
        editor.chain().focus().toggleTaskList().run()
        return true
      },

      // Cmd+Option+C toggles code block
      'Mod-Alt-c': ({ editor }) => {
        editor.chain().focus().toggleCodeBlock().run()
        return true
      },

      // Cmd+Enter toggles checkbox
      'Mod-Enter': ({ editor }) => {
        if (editor.isActive('taskItem')) {
          // Toggle the checked state
          const { state } = editor
          const { $from } = state.selection
          // Find the taskItem node
          let depth = $from.depth
          while (depth > 0) {
            const node = $from.node(depth)
            if (node.type.name === 'taskItem') {
              const pos = $from.before(depth)
              editor.chain()
                .command(({ tr }) => {
                  tr.setNodeAttribute(pos, 'checked', !node.attrs.checked)
                  return true
                })
                .run()
              return true
            }
            depth--
          }
        }
        return false
      },

      // Ctrl+Cmd+Up moves list item up
      'Mod-Ctrl-ArrowUp': ({ editor }) => {
        return moveListItem(editor, 'up')
      },

      // Ctrl+Cmd+Down moves list item down
      'Mod-Ctrl-ArrowDown': ({ editor }) => {
        return moveListItem(editor, 'down')
      },

      // Backspace at start of list item: lift to paragraph instead of joining with previous
      'Backspace': ({ editor }) => {
        const { state } = editor
        const { $from, empty } = state.selection

        // Only handle when cursor is at the very start of a list item and selection is empty
        if (!empty) return false

        const isListItem = editor.isActive('listItem') || editor.isActive('taskItem')
        if (!isListItem) return false

        // Check if cursor is at the start of the text content
        const parentOffset = $from.parentOffset
        if (parentOffset !== 0) return false

        // Lift the list item to a paragraph (stay on same line)
        if (editor.isActive('taskItem')) {
          return editor.chain().liftListItem('taskItem').run()
        }
        if (editor.isActive('listItem')) {
          return editor.chain().liftListItem('listItem').run()
        }

        return false
      },
    }
  },
})

function moveListItem(editor, direction) {
  const { state } = editor
  const { $from } = state.selection

  // Find the closest list item
  let depth = $from.depth
  while (depth > 0) {
    const name = $from.node(depth).type.name
    if (name === 'listItem' || name === 'taskItem') break
    depth--
  }
  if (depth === 0) return false

  const parent = $from.node(depth - 1)
  const index = $from.index(depth - 1)
  const item = parent.child(index)
  const itemPos = $from.before(depth)
  const cursorPos = $from.pos

  if (direction === 'up') {
    if (index === 0) return false
    const prev = parent.child(index - 1)
    const rangeStart = itemPos - prev.nodeSize
    const newCursorPos = cursorPos - prev.nodeSize

    const tr = state.tr
    tr.replaceWith(rangeStart, itemPos + item.nodeSize, [item, prev])
    tr.setSelection(TextSelection.create(tr.doc, newCursorPos))
    tr.scrollIntoView()
    editor.view.dispatch(tr)
    return true
  } else {
    if (index >= parent.childCount - 1) return false
    const next = parent.child(index + 1)
    const newCursorPos = cursorPos + next.nodeSize

    const tr = state.tr
    tr.replaceWith(itemPos, itemPos + item.nodeSize + next.nodeSize, [next, item])
    tr.setSelection(TextSelection.create(tr.doc, newCursorPos))
    tr.scrollIntoView()
    editor.view.dispatch(tr)
    return true
  }
}

function createEditor() {
  editor = new Editor({
    element: document.getElementById('editor'),
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
      }),
      TaskList,
      TaskItem.configure({ nested: true }),
      Link.configure({ openOnClick: false }),
      CustomImage.configure({ inline: false, allowBase64: false }),
      Placeholder.configure({ placeholder: 'Start typing...' }),
      Markdown.configure({
        html: false,
        transformPastedText: true,
        transformCopiedText: true,
      }),
      ExtraShortcuts,
      TaskListInputRule,
    ],
    autofocus: true,
    onUpdate: ({ editor }) => {
      const json = JSON.stringify(editor.getJSON())
      window.webkit?.messageHandlers?.bridge?.postMessage(
        JSON.stringify({ type: 'contentChanged', json: json })
      )
    },
    onTransaction: () => {
      updateToolbarState()
    },
  })

  // Notify Swift that editor is ready
  window.webkit?.messageHandlers?.bridge?.postMessage(
    JSON.stringify({ type: 'ready' })
  )
}

// Toolbar state management
function updateToolbarState() {
  if (!editor) return

  const buttons = {
    'btn-h1': editor.isActive('heading', { level: 1 }),
    'btn-h2': editor.isActive('heading', { level: 2 }),
    'btn-h3': editor.isActive('heading', { level: 3 }),
    'btn-bold': editor.isActive('bold'),
    'btn-italic': editor.isActive('italic'),
    'btn-strike': editor.isActive('strike'),
    'btn-code': editor.isActive('code'),
    'btn-link': editor.isActive('link'),
    'btn-checkbox': editor.isActive('taskList'),
    'btn-bullet': editor.isActive('bulletList'),
    'btn-ordered': editor.isActive('orderedList'),
    'btn-blockquote': editor.isActive('blockquote'),
    'btn-codeblock': editor.isActive('codeBlock'),
  }

  for (const [id, active] of Object.entries(buttons)) {
    const el = document.getElementById(id)
    if (el) {
      el.classList.toggle('active', active)
    }
  }
}

// Toolbar actions
window.toolbarAction = function(action) {
  if (!editor) return

  switch (action) {
    case 'h1':
      editor.chain().focus().toggleHeading({ level: 1 }).run()
      break
    case 'h2':
      editor.chain().focus().toggleHeading({ level: 2 }).run()
      break
    case 'h3':
      editor.chain().focus().toggleHeading({ level: 3 }).run()
      break
    case 'bold':
      editor.chain().focus().toggleBold().run()
      break
    case 'italic':
      editor.chain().focus().toggleItalic().run()
      break
    case 'strike':
      editor.chain().focus().toggleStrike().run()
      break
    case 'code':
      editor.chain().focus().toggleCode().run()
      break
    case 'link':
      if (editor.isActive('link')) {
        editor.chain().focus().unsetLink().run()
      } else {
        showLinkInput()
        return // don't refocus editor
      }
      break
    case 'checkbox':
      editor.chain().focus().toggleTaskList().run()
      break
    case 'bullet':
      editor.chain().focus().toggleBulletList().run()
      break
    case 'ordered':
      editor.chain().focus().toggleOrderedList().run()
      break
    case 'blockquote':
      editor.chain().focus().toggleBlockquote().run()
      break
    case 'codeblock':
      editor.chain().focus().toggleCodeBlock().run()
      break
  }

}

// Inline link input
function showLinkInput() {
  // Remove existing if any
  const existing = document.getElementById('link-input-bar')
  if (existing) existing.remove()

  const bar = document.createElement('div')
  bar.id = 'link-input-bar'
  bar.innerHTML = `
    <input type="text" id="link-url-input" placeholder="Paste or type URL…" spellcheck="false" autocomplete="off" />
    <div id="link-cancel" class="link-bar-btn">✕</div>
  `
  document.body.appendChild(bar)

  const input = document.getElementById('link-url-input')
  const cancel = document.getElementById('link-cancel')

  input.focus()

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault()
      const url = input.value.trim()
      bar.remove()
      if (url) {
        editor.chain().focus().setLink({ href: url }).run()
      } else {
        editor.commands.focus()
      }
    } else if (e.key === 'Escape') {
      e.preventDefault()
      bar.remove()
      editor.commands.focus()
    }
  })

  cancel.addEventListener('click', () => {
    bar.remove()
    editor.commands.focus()
  })
}

// Called from Swift to move list item up/down
window.moveListItemFromSwift = function(direction) {
  if (editor) {
    moveListItem(editor, direction)
  }
}

// Called from Swift to load content (JSON or markdown for backward compat)
window.loadContent = function(content) {
  if (editor) {
    let parsed
    try {
      parsed = JSON.parse(content)
    } catch (e) {
      // Not JSON — treat as markdown (old format)
      parsed = content
    }
    editor.commands.setContent(parsed)
    // Reset editor state to clear undo history — prevents Cmd+Z crossing between notes
    const freshState = EditorState.create({
      doc: editor.state.doc,
      plugins: editor.state.plugins,
    })
    editor.view.updateState(freshState)
  }
}

// Called from Swift to get current markdown
window.getMarkdown = function() {
  if (editor) {
    return editor.storage.markdown.getMarkdown()
  }
  return ''
}

// Called from Swift to focus the editor
window.focusEditor = function() {
  if (editor) {
    editor.commands.focus()
  }
}

// Heading dropdown
window.toggleHeadingMenu = function() {
  const menu = document.getElementById('heading-menu')
  if (menu) {
    menu.classList.toggle('visible')
  }
}

// Close heading menu when clicking elsewhere
document.addEventListener('click', (e) => {
  if (!e.target.closest('#btn-heading') && !e.target.closest('#heading-menu')) {
    const menu = document.getElementById('heading-menu')
    if (menu) menu.classList.remove('visible')
  }
})

// Called from Swift to move list items
window.moveListItemBridge = function(direction) {
  if (editor) {
    moveListItem(editor, direction)
  }
}

// Called from Swift to set dimmed state
window.setDimmed = function(dimmed) {
  if (dimmed) {
    document.body.classList.add('dimmed')
  } else {
    document.body.classList.remove('dimmed')
  }
}

// Toolbar tooltip on hover
function setupToolbarTooltips() {
  let activeTooltip = null

  document.querySelectorAll('.toolbar-btn[data-tooltip]').forEach(btn => {
    btn.addEventListener('mouseenter', () => {
      if (activeTooltip) activeTooltip.remove()

      const tip = document.createElement('div')
      tip.className = 'toolbar-tooltip'

      const label = document.createElement('span')
      label.className = 'tip-label'
      label.textContent = btn.dataset.tooltip
      tip.appendChild(label)

      if (btn.dataset.keys) {
        btn.dataset.keys.split(' ').forEach(k => {
          const key = document.createElement('span')
          key.className = 'tip-key'
          key.textContent = k
          tip.appendChild(key)
        })
      }

      document.body.appendChild(tip)

      // Position above the button, clamp to viewport edges
      const rect = btn.getBoundingClientRect()
      let left = rect.left + rect.width / 2 - tip.offsetWidth / 2
      const margin = 8
      if (left + tip.offsetWidth > window.innerWidth - margin) {
        left = window.innerWidth - tip.offsetWidth - margin
      }
      if (left < margin) left = margin
      tip.style.left = left + 'px'
      tip.style.bottom = (window.innerHeight - rect.top + 6) + 'px'

      activeTooltip = tip
    })

    btn.addEventListener('mouseleave', () => {
      if (activeTooltip) {
        activeTooltip.remove()
        activeTooltip = null
      }
    })
  })
}

// Image paste/drop support
function setupImageHandlers() {
  const editorEl = document.getElementById('editor')

  // Handle paste
  editorEl.addEventListener('paste', (e) => {
    const items = e.clipboardData?.items
    if (!items) return

    for (const item of items) {
      if (item.type.startsWith('image/')) {
        e.preventDefault()
        const file = item.getAsFile()
        if (file) sendImageToSwift(file)
        return
      }
    }
  })

  // Handle drag & drop
  editorEl.addEventListener('drop', (e) => {
    const files = e.dataTransfer?.files
    if (!files) return

    for (const file of files) {
      if (file.type.startsWith('image/')) {
        e.preventDefault()
        sendImageToSwift(file)
        return
      }
    }
  })

  editorEl.addEventListener('dragover', (e) => {
    if (e.dataTransfer?.types?.includes('Files')) {
      e.preventDefault()
    }
  })
}

function sendImageToSwift(file) {
  const reader = new FileReader()
  reader.onload = () => {
    const base64 = reader.result.split(',')[1]
    window.webkit?.messageHandlers?.bridge?.postMessage(
      JSON.stringify({ type: 'imagePaste', data: base64, mimeType: file.type })
    )
  }
  reader.readAsDataURL(file)
}

// Called from Swift after image is saved to disk
window.insertImage = function(url) {
  if (editor) {
    editor.chain().focus().setImage({ src: url }).run()
    // Move cursor after the image so user can paste another immediately
    setTimeout(() => {
      editor.commands.focus('end')
    }, 50)
  }
}

// --- Image UI: wrappers, popup, metadata, delete, grid ---


function openImagePopup(src) {
  const overlay = document.createElement('div')
  overlay.className = 'image-popup-overlay'

  const container = document.createElement('div')
  container.className = 'image-popup-container'

  const popupImg = document.createElement('img')
  popupImg.src = src

  const btn = document.createElement('button')
  btn.className = 'image-popup-btn'
  btn.textContent = 'Open in Preview'
  btn.addEventListener('click', (e) => {
    e.stopPropagation()
    // Ask Swift to open in Preview
    window.webkit?.messageHandlers?.bridge?.postMessage(
      JSON.stringify({ type: 'openInPreview', src: src })
    )
  })

  // Close X button
  const closeBtn = document.createElement('div')
  closeBtn.className = 'image-popup-close'
  closeBtn.textContent = '✕'
  closeBtn.addEventListener('click', (e) => {
    e.stopPropagation()
    overlay.remove()
  })

  container.appendChild(popupImg)
  container.appendChild(btn)
  container.appendChild(closeBtn)
  overlay.appendChild(container)
  document.body.appendChild(overlay)

  // Click overlay (outside image) to close
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) overlay.remove()
  })

  // Escape to close
  const escHandler = (e) => {
    if (e.key === 'Escape') {
      overlay.remove()
      document.removeEventListener('keydown', escHandler)
    }
  }
  document.addEventListener('keydown', escHandler)
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  createEditor()
  setupToolbarTooltips()
  setupImageHandlers()
})
