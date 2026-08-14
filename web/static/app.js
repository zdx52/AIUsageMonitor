// ── autonovel-cn Web UI ──

// Toast notification
function toast(msg, type = "ok") {
    let el = document.querySelector(".toast");
    if (!el) {
        el = document.createElement("div");
        el.className = "toast";
        document.body.appendChild(el);
    }
    el.textContent = msg;
    el.className = `toast toast-${type} show`;
    setTimeout(() => el.classList.remove("show"), 3000);
}

// Auto-save for editor
let saveTimer = null;
function setupAutoSave() {
    const ta = document.getElementById("editor-textarea");
    const saveBtn = document.getElementById("save-btn");
    if (!ta) return;

    function doSave() {
        const content = ta.value;
        const file = ta.dataset.file;
        const slug = ta.dataset.slug;
        if (!file || !slug) return;

        if (saveBtn) saveBtn.disabled = true;
        fetch(`/api/novels/${slug}/save`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ file, content }),
        })
        .then(r => r.json())
        .then(data => {
            if (data.ok) {
                if (saveBtn) saveBtn.textContent = "✅ 已保存";
                updatePreview(content);
            } else {
                toast("保存失败: " + (data.error || "未知错误"), "err");
            }
        })
        .catch(e => toast("保存失败: " + e.message, "err"))
        .finally(() => {
            if (saveBtn) {
                saveBtn.disabled = false;
                setTimeout(() => { saveBtn.textContent = "💾 保存"; }, 2000);
            }
        });
    }

    // Auto-save on content change (debounced)
    ta.addEventListener("input", () => {
        if (saveTimer) clearTimeout(saveTimer);
        saveTimer = setTimeout(doSave, 1500);
        if (saveBtn) saveBtn.textContent = "💾 保存";
        updatePreview(ta.value);
    });

    // Manual save
    if (saveBtn) {
        saveBtn.addEventListener("click", doSave);
    }

    // Ctrl+S
    ta.addEventListener("keydown", (e) => {
        if ((e.ctrlKey || e.metaKey) && e.key === "s") {
            e.preventDefault();
            doSave();
        }
    });
}

// Update markdown preview
function updatePreview(md) {
    const preview = document.getElementById("editor-preview");
    if (!preview) return;
    // Simple markdown rendering (client-side)
    let html = md
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        // Headers
        .replace(/^### (.+)$/gm, "<h3>$1</h3>")
        .replace(/^## (.+)$/gm, "<h2>$1</h2>")
        .replace(/^# (.+)$/gm, "<h1>$1</h1>")
        // Bold/italic
        .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
        .replace(/\*(.+?)\*/g, "<em>$1</em>")
        // Code blocks
        .replace(/```(\w*)\n([\s\S]*?)```/g, "<pre><code>$2</code></pre>")
        // Inline code
        .replace(/`([^`]+)`/g, "<code>$1</code>")
        // Blockquote
        .replace(/^> (.+)$/gm, "<blockquote>$1</blockquote>")
        // Horizontal rule
        .replace(/^---$/gm, "<hr>")
        // Unordered list
        .replace(/^- (.+)$/gm, "<li>$1</li>")
        .replace(/(<li>.*<\/li>\n?)+/g, "<ul>$&</ul>")
        // Paragraphs (double newlines)
        .replace(/\n\n/g, "</p><p>")
        .replace(/^(.+)$/gm, (m) => {
            if (m.startsWith("<")) return m;
            return m;
        });
    // Wrap in <p>
    if (!html.startsWith("<")) {
        html = "<p>" + html + "</p>";
    }
    preview.innerHTML = html;
}

// ── Pipeline ──────────────────────────────────────
let logPollTimer = null;

function startPipeline(slug, script, args = "") {
    const logWin = document.getElementById("log-window");
    const btns = document.querySelectorAll(".pipeline-btn");
    if (!logWin) return;

    // Clear log
    logWin.innerHTML = "";
    logWin.innerHTML += `<div class="log-line log-info">> 启动: ${script} ${args}</div>\n`;

    // Disable buttons
    btns.forEach(b => b.disabled = true);

    fetch(`/api/novels/${slug}/run`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ script, args }),
    })
    .then(r => r.json())
    .then(data => {
        if (!data.ok) {
            logWin.innerHTML += `<div class="log-line log-err">❌ ${data.error}</div>\n`;
            btns.forEach(b => b.disabled = false);
            return;
        }
        // Start polling logs
        pollLogs(slug, btns);
    })
    .catch(e => {
        logWin.innerHTML += `<div class="log-line log-err">❌ ${e.message}</div>\n`;
        btns.forEach(b => b.disabled = false);
    });
}

function pollLogs(slug, btns) {
    if (logPollTimer) clearInterval(logPollTimer);

    logPollTimer = setInterval(() => {
        fetch(`/api/novels/${slug}/logs`)
        .then(r => r.json())
        .then(data => {
            const logWin = document.getElementById("log-window");
            if (!logWin) return;

            data.lines.forEach(line => {
                let cls = "log-line";
                if (line.includes("[exit code:")) cls += " log-info";
                else if (line.includes("error") || line.includes("Error") || line.includes("ERROR")) cls += " log-err";
                else if (line.includes("✅") || line.includes("完成") || line.includes("saved")) cls += " log-ok";
                logWin.innerHTML += `<div class="${cls}">${escapeHtml(line)}</div>`;
            });
            logWin.scrollTop = logWin.scrollHeight;

            if (!data.running) {
                clearInterval(logPollTimer);
                logPollTimer = null;
                logWin.innerHTML += `<div class="log-line log-info">--- 完成 ---</div>\n`;
                btns.forEach(b => b.disabled = false);
            }
        })
        .catch(() => {});
    }, 500);
}

function stopPipeline(slug) {
    fetch(`/api/novels/${slug}/stop`, { method: "POST" })
    .then(r => r.json())
    .then(data => {
        if (data.ok) {
            toast("已停止");
            if (logPollTimer) {
                clearInterval(logPollTimer);
                logPollTimer = null;
            }
            document.querySelectorAll(".pipeline-btn").forEach(b => b.disabled = false);
        }
    })
    .catch(e => toast("停止失败: " + e.message, "err"));
}

function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
}

// ── Export ──────────────────────────────────────────
function runExport(slug) {
    const btn = document.getElementById("export-btn");
    const out = document.getElementById("export-output");
    if (!btn || !out) return;

    btn.disabled = true;
    btn.textContent = "⏳ 导出中...";
    out.innerHTML = "";

    fetch(`/api/novels/${slug}/export`, { method: "POST" })
    .then(r => r.json())
    .then(data => {
        if (data.ok) {
            out.innerHTML += `<div class="log-line log-ok">✅ 导出成功</div>\n`;
            if (data.zip) {
                out.innerHTML += `<div class="log-line log-info"><a href="/api/novels/${slug}/download/${data.zip}" class="btn btn-sm">📥 下载 ${data.zip}</a></div>\n`;
            }
            if (data.output) {
                out.innerHTML += `<pre class="log-window" style="height:200px;margin-top:8px">${escapeHtml(data.output)}</pre>`;
            }
        } else {
            out.innerHTML += `<div class="log-line log-err">❌ ${data.error || "导出失败"}</div>\n`;
        }
    })
    .catch(e => {
        out.innerHTML += `<div class="log-line log-err">❌ ${e.message}</div>\n`;
    })
    .finally(() => {
        btn.disabled = false;
        btn.textContent = "📤 导出";
    });
}

// ── Init ────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", () => {
    setupAutoSave();
});
