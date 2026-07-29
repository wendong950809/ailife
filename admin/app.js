// AI Life 后台管理系统 - 前端逻辑

// ============================================
// 认证状态
// ============================================
let authUser = JSON.parse(localStorage.getItem('admin_user') || 'null');
let supabaseConfig = null;

let currentPage = 'dashboard';
let currentMessages = [];
let currentFacts = [];
let msgFilter = { role: '', extracted: '', keyword: '' };
let factsFilter = { fact_type: '', keyword: '' };
let logsFilter = { status: '', category: '', keyword: '' };
let aiLogsFilter = { status: '', call_type: '', keyword: '' };
let usersFilter = { keyword: '' };

const pageTitle = {
  dashboard: '仪表盘', messages: '消息管理', facts: '事实管理',
  logs: '操作日志', 'ai-logs': 'AI调用日志', check: '数据检查', users: '用户管理'
};

const factTypeNames = {
  action: '行为', person: '人物', reference: '引用', time: '时间',
  location: '地点', emotion: '情绪', object: '物品',
  intent: '意图', state: '状态'
};

const pageSizeOptions = [10, 20, 50, 100];

// ============================================
// API 调用
// ============================================
async function api(path, options) {
  const res = await fetch('/api' + path, options);
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: '请求失败' }));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}

async function apiPost(path, body) {
  return api(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  });
}

// ============================================
// 认证
// ============================================
async function loadConfig() {
  try {
    const res = await fetch('/api/config');
    supabaseConfig = await res.json();
  } catch (e) {
    console.error('加载配置失败:', e);
  }
}

async function doLogin() {
  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;
  const errorDiv = document.getElementById('login-error');
  errorDiv.textContent = '';

  if (!email || !password) {
    errorDiv.textContent = '请输入邮箱和密码';
    return;
  }

  try {
    const res = await fetch(`${supabaseConfig.supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: {
        'apikey': supabaseConfig.anonKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ email, password })
    });

    if (!res.ok) {
      const err = await res.json();
      throw new Error(err.error_description || err.msg || err.message || '登录失败');
    }

    const data = await res.json();
    localStorage.setItem('admin_token', data.access_token);
    localStorage.setItem('admin_user', JSON.stringify(data.user));
    authUser = data.user;
    showAdmin();
  } catch (e) {
    errorDiv.textContent = e.message;
  }
}

function logout() {
  localStorage.removeItem('admin_token');
  localStorage.removeItem('admin_user');
  authUser = null;
  showLogin();
}

function showLogin() {
  document.getElementById('login-page').style.display = 'flex';
  document.getElementById('admin-layout').style.display = 'none';
}

function showAdmin() {
  document.getElementById('login-page').style.display = 'none';
  document.getElementById('admin-layout').style.display = 'flex';

  const userInfo = document.getElementById('user-info');
  if (authUser) {
    userInfo.textContent = authUser.email || '';
  }

  navigate('dashboard');
}

// ============================================
// 工具函数
// ============================================
function formatTime(iso) {
  if (!iso) return '-';
  return new Date(iso).toLocaleString('zh-CN', { hour12: false });
}

function escapeHtml(s) {
  if (s == null) return '';
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function userDisplay(userName, userId) {
  return `<span class="user-name">${escapeHtml(userName || '-')}</span><br><span class="user-id-small">${escapeHtml(userId ? userId.substring(0, 8) : '')}</span>`;
}

function extractedBadge(extracted, error) {
  if (error) return '<span class="badge badge-error" title="' + escapeHtml(error) + '">提取失败</span>';
  if (extracted) return '<span class="badge badge-success">已提取</span>';
  return '<span class="badge badge-warning">未提取</span>';
}

function statusBadge(status) {
  if (status === 'success' || status === 'succeeded') return '<span class="badge badge-success">成功</span>';
  if (status === 'failed') return '<span class="badge badge-error">失败</span>';
  if (status === 'pending') return '<span class="badge badge-warning">进行中</span>';
  return '<span class="badge badge-default">' + escapeHtml(status || '-') + '</span>';
}

function roleBadge(role) {
  if (role === 'user') return '<span class="badge badge-info">用户</span>';
  if (role === 'assistant') return '<span class="badge badge-default">AI</span>';
  return '<span class="badge badge-default">' + escapeHtml(role) + '</span>';
}

function factTypeBadge(type) {
  const name = factTypeNames[type] || type;
  return '<span class="ft-' + (type || 'other') + '">' + escapeHtml(name) + '</span>';
}

function confidenceBar(val) {
  const pct = Math.round((val || 0) * 100);
  const color = pct >= 80 ? 'var(--success)' : pct >= 60 ? 'var(--warning)' : 'var(--error)';
  return '<div style="display:flex;align-items:center;gap:6px"><div style="width:50px;height:6px;background:#f0f0f0;border-radius:3px"><div style="width:' + pct + '%;height:100%;background:' + color + ';border-radius:3px"></div></div><span style="font-size:12px;color:var(--text-tertiary)">' + pct + '%</span></div>';
}

function showToast(msg, type) {
  const toast = document.getElementById('toast');
  toast.textContent = msg;
  toast.className = 'toast ' + (type || 'success');
  toast.style.display = 'block';
  setTimeout(() => { toast.style.display = 'none'; }, 3000);
}

function showModal(title, html) {
  document.getElementById('modal-title').textContent = title;
  document.getElementById('modal-body').innerHTML = html;
  document.getElementById('modal-overlay').style.display = 'flex';
}

function closeModal() {
  document.getElementById('modal-overlay').style.display = 'none';
}

// ============================================
// 页面路由
// ============================================
function navigate(page) {
  currentPage = page;
  document.getElementById('page-title').textContent = pageTitle[page] || page;
  document.querySelectorAll('.nav-item').forEach(el => {
    el.classList.toggle('active', el.dataset.page === page);
  });
  refresh();
}

function refresh() {
  const container = document.getElementById('page-content');
  container.innerHTML = '<div class="loading"><div class="spinner"></div></div>';

  switch (currentPage) {
    case 'dashboard': renderDashboard(); break;
    case 'messages': renderMessages(1); break;
    case 'facts': renderFacts(1); break;
    case 'logs': renderLogs(1); break;
    case 'ai-logs': renderAiLogs(1); break;
    case 'check': renderCheck(); break;
    case 'users': renderUsers(1); break;
  }
}

// ============================================
// 仪表盘
// ============================================
async function renderDashboard() {
  try {
    const d = await api('/dashboard');
    document.getElementById('page-content').innerHTML = `
      <div class="stats-grid">
        <div class="stat-card"><div class="label">用户总数</div><div class="value">${d.users}</div></div>
        <div class="stat-card"><div class="label">消息总数</div><div class="value">${d.messages}</div></div>
        <div class="stat-card"><div class="label">用户消息</div><div class="value">${d.userMessages}</div></div>
        <div class="stat-card"><div class="label">提取事实数</div><div class="value success">${d.facts}</div></div>
        <div class="stat-card"><div class="label">未提取消息</div><div class="value ${d.unextracted > 0 ? 'warning' : ''}">${d.unextracted}</div></div>
        <div class="stat-card"><div class="label">数据不一致</div><div class="value ${d.inconsistent > 0 ? 'danger' : 'success'}">${d.inconsistent}</div></div>
        <div class="stat-card"><div class="label">失败操作</div><div class="value ${d.failedLogs > 0 ? 'danger' : 'success'}">${d.failedLogs}</div></div>
      </div>
      <div class="check-section">
        <h3>快速操作</h3>
        <div style="display:flex;gap:12px;flex-wrap:wrap;margin-top:8px">
          <button class="btn" onclick="navigate('check')">数据一致性检查</button>
          <button class="btn btn-outline" onclick="navigate('messages')">查看消息</button>
          <button class="btn btn-outline" onclick="navigate('facts')">查看事实</button>
          <button class="btn btn-outline" onclick="navigate('logs')">查看日志</button>
        </div>
      </div>
    `;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

// ============================================
// 消息管理（含用户名、分页、搜索、序号）
// ============================================
async function renderMessages(page, limit) {
  limit = limit || 20;
  try {
    const params = new URLSearchParams({ page: page || 1, limit: limit });
    if (msgFilter.role) params.set('role', msgFilter.role);
    if (msgFilter.extracted) params.set('extracted', msgFilter.extracted);
    if (msgFilter.keyword) params.set('keyword', msgFilter.keyword);

    const res = await api('/messages?' + params.toString());
    const data = res.data || [];
    currentMessages = data;

    let html = `
      <div class="filter-bar">
        <input type="text" placeholder="搜索消息内容..." value="${escapeHtml(msgFilter.keyword)}" 
               oninput="msgFilter.keyword=this.value" 
               onkeydown="if(event.key==='Enter') renderMessages(1)">
        <select onchange="msgFilter.role=this.value;renderMessages(1)">
          <option value="">全部角色</option>
          <option value="user" ${msgFilter.role==='user'?'selected':''}>用户</option>
          <option value="assistant" ${msgFilter.role==='assistant'?'selected':''}>AI</option>
        </select>
        <select onchange="msgFilter.extracted=this.value;renderMessages(1)">
          <option value="">全部状态</option>
          <option value="true" ${msgFilter.extracted==='true'?'selected':''}>已提取</option>
          <option value="false" ${msgFilter.extracted==='false'?'selected':''}>未提取</option>
        </select>
        <select onchange="renderMessages(1, parseInt(this.value))">
          ${pageSizeOptions.map(s => `<option value="${s}" ${s===limit?'selected':''}>${s}条/页</option>`).join('')}
        </select>
        <button class="btn btn-sm" onclick="renderMessages(1)">搜索</button>
        <button class="btn btn-sm btn-success" onclick="batchReextract()" style="margin-left:auto">批量提取所有未提取消息</button>
      </div>
    `;

    if (data.length === 0) {
      html += '<div class="empty">暂无消息</div>';
    } else {
      html += '<div class="table-wrap"><table><thead><tr>';
      html += '<th>序号</th><th>时间</th><th>用户</th><th>角色</th><th>内容</th><th>提取状态</th><th>事实条数</th><th>操作</th>';
      html += '</tr></thead><tbody>';
      const startIdx = (page - 1) * limit + 1;
      for (let i = 0; i < data.length; i++) {
        const m = data[i];
        const idx = startIdx + i;
        html += '<tr>';
        html += '<td style="text-align:center;width:60px">' + idx + '</td>';
        html += '<td style="white-space:nowrap">' + formatTime(m.created_at) + '</td>';
        html += '<td>' + userDisplay(m.user_name, m.user_id) + '</td>';
        html += '<td>' + roleBadge(m.role) + '</td>';
        html += '<td class="content-cell" title="' + escapeHtml(m.content) + '">' + escapeHtml(m.content) + '</td>';
        html += '<td>' + extractedBadge(m.extracted, m.extraction_error) + '</td>';
        html += '<td style="text-align:center">' + (m.fact_count || 0) + '</td>';
        html += '<td style="white-space:nowrap">';
        html += '<button class="btn btn-sm btn-outline" onclick="viewMessage(\'' + m.id + '\')">详情</button>';
        if (m.role === 'user') {
          html += ' <button class="btn btn-sm" onclick="reextract(\'' + m.id + '\')">重新提取</button>';
        }
        html += '</td>';
        html += '</tr>';
      }
      html += '</tbody></table></div>';
      html += paginationHtml(res.total, page, limit, 'renderMessages');
    }

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

function viewMessage(id) {
  const msg = currentMessages.find(m => m.id === id);
  if (!msg) { showToast('消息未找到', 'error'); return; }
  let html = '';
  html += '<div class="detail-row"><div class="detail-label">ID</div><div class="detail-value">' + escapeHtml(msg.id) + '</div></div>';
  html += '<div class="detail-row"><div class="detail-label">用户</div><div class="detail-value">' + userDisplay(msg.user_name, msg.user_id) + '</div></div>';
  html += '<div class="detail-row"><div class="detail-label">角色</div><div class="detail-value">' + roleBadge(msg.role) + '</div></div>';
  html += '<div class="detail-row"><div class="detail-label">时间</div><div class="detail-value">' + formatTime(msg.created_at) + '</div></div>';
  html += '<div class="detail-row"><div class="detail-label">提取状态</div><div class="detail-value">' + extractedBadge(msg.extracted, msg.extraction_error) + '</div></div>';
  if (msg.extraction_error) {
    html += '<div class="detail-row"><div class="detail-label">错误信息</div><div class="detail-value" style="color:var(--error)">' + escapeHtml(msg.extraction_error) + '</div></div>';
  }
  html += '<div class="detail-row"><div class="detail-label">内容</div><div class="detail-value"><pre>' + escapeHtml(msg.content) + '</pre></div></div>';
  showModal('消息详情', html);
}

async function reextract(id) {
  if (!confirm('确定要重新提取这条消息的事实吗？')) return;
  showToast('正在提取...', 'success');
  try {
    const result = await apiPost('/reextract', { message_id: id });
    showToast('成功提取 ' + result.fact_count + ' 条事实', 'success');
    renderMessages(1);
  } catch (e) {
    showToast('提取失败: ' + e.message, 'error');
  }
}

async function batchReextract() {
  if (!confirm('确定要批量提取所有未提取的消息吗？这可能需要一些时间。')) return;
  showToast('正在批量提取...', 'success');
  try {
    const result = await apiPost('/reextract/all', {});
    let msg = `批量提取完成！共处理 ${result.count} 条消息`;
    if (result.success_count > 0) msg += `，成功 ${result.success_count} 条`;
    if (result.failed_count > 0) msg += `，失败 ${result.failed_count} 条`;
    showToast(msg, result.failed_count > 0 ? 'error' : 'success');
    if (result.failed_messages && result.failed_messages.length > 0) {
      console.log('批量提取失败详情:', result.failed_messages);
    }
    renderMessages(1);
  } catch (e) {
    showToast('批量提取失败: ' + e.message, 'error');
  }
}

// ============================================
// 事实管理（按组展示、分页、搜索）
// ============================================
let currentFactGroups = [];

async function renderFacts(page, limit) {
  limit = limit || 20;
  try {
    const params = new URLSearchParams({ page: page || 1, limit: limit });
    if (factsFilter.fact_type) params.set('fact_type', factsFilter.fact_type);
    if (factsFilter.keyword) params.set('keyword', factsFilter.keyword);

    const res = await api('/fact-groups?' + params.toString());
    const data = res.data || [];
    currentFactGroups = data;

    let html = `
      <div class="stats-grid">
        <div class="stat-card"><div class="label">事实组总数</div><div class="value">${res.total}</div></div>
        <div class="stat-card"><div class="label">有事实的组</div><div class="value success">${data.filter(g => (g.facts || []).length > 0).length}</div></div>
        <div class="stat-card"><div class="label">空事实组</div><div class="value warning">${data.filter(g => (g.facts || []).length === 0).length}</div></div>
      </div>
      <div class="filter-bar">
        <input type="text" placeholder="搜索摘要或内容..." value="${escapeHtml(factsFilter.keyword)}" 
               oninput="factsFilter.keyword=this.value" 
               onkeydown="if(event.key==='Enter') renderFacts(1)">
        <select onchange="factsFilter.fact_type=this.value;renderFacts(1)">
          <option value="">全部类型</option>
          ${Object.entries(factTypeNames).map(([k,v]) => `<option value="${k}" ${factsFilter.fact_type===k?'selected':''}>${v}</option>`).join('')}
        </select>
        <select onchange="renderFacts(1, parseInt(this.value))">
          ${pageSizeOptions.map(s => `<option value="${s}" ${s===limit?'selected':''}>${s}条/页</option>`).join('')}
        </select>
        <button class="btn btn-sm" onclick="renderFacts(1)">搜索</button>
      </div>
    `;

    if (data.length === 0) {
      html += '<div class="empty">暂无事实组数据</div>';
    } else {
      const startIdx = (page - 1) * limit + 1;
      for (let i = 0; i < data.length; i++) {
        const g = data[i];
        const idx = startIdx + i;
        const facts = g.facts || [];
        let factsHtml = '';
        for (const f of facts) {
          factsHtml += `
            <div class="fact-item">
              <span class="fact-type-badge ft-${f.fact_type || 'other'}">${escapeHtml(factTypeNames[f.fact_type] || f.fact_type)}</span>
              <div class="fact-content">
                <span class="fact-key">${escapeHtml(f.fact_key)}</span>
                <span class="fact-value">${escapeHtml(f.fact_value)}</span>
              </div>
              <span class="fact-conf">${Math.round((f.confidence || 0) * 100)}%</span>
            </div>
          `;
        }

        html += `
          <div class="group-card ${facts.length > 0 ? 'has-facts' : 'empty-group'}">
            <div class="group-header">
              <div class="group-summary-wrap">
                <div class="group-summary ${facts.length === 0 ? 'empty-text' : ''}"><span style="font-weight:600;color:#999;margin-right:8px">[${idx}]</span>${escapeHtml(g.summary || '(无摘要)')}</div>
                <div class="group-meta">
                  <span>${formatTime(g.created_at)}</span>
                  <span>${userDisplay(g.user_name, g.user_id)}</span>
                </div>
              </div>
              <div class="group-stats">
                <span class="stat-badge ${facts.length > 0 ? 'has-data' : 'zero'}">${facts.length} 条事实</span>
              </div>
            </div>
            <div class="group-facts ${facts.length === 0 ? 'empty-facts' : ''}">
              ${facts.length === 0 ? '该消息未提取到有效事实' : `<div class="facts-grid">${factsHtml}</div>`}
            </div>
            <div class="group-source">
              <span class="source-label">来源</span>
              <span class="source-text">${escapeHtml(g.message_content || '')}</span>
            </div>
            <div class="group-actions">
              <button class="btn btn-sm btn-outline" onclick="viewGroup('${g.id}')">详情</button>
              <button class="btn btn-sm" onclick="reextract('${g.message_id}')">重新提取</button>
              <button class="btn btn-sm btn-danger" onclick="deleteGroup('${g.id}')">删除组</button>
            </div>
          </div>
        `;
      }
      html += paginationHtml(res.total, page, limit, 'renderFacts');
    }

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

function viewGroup(id) {
  const group = currentFactGroups.find(g => g.id === id);
  if (!group) { showToast('事实组未找到', 'error'); return; }
  const facts = group.facts || [];
  let factsHtml = '';
  for (const f of facts) {
    factsHtml += `
      <div class="detail-row">
        <div class="detail-label">${factTypeBadge(f.fact_type)} ${escapeHtml(f.fact_key)}</div>
        <div class="detail-value">${escapeHtml(f.fact_value)} <span style="color:#999;font-size:12px">${Math.round((f.confidence || 0) * 100)}%</span></div>
      </div>
    `;
  }
  let html = `
    <div class="detail-row"><div class="detail-label">ID</div><div class="detail-value">${escapeHtml(group.id)}</div></div>
    <div class="detail-row"><div class="detail-label">用户</div><div class="detail-value">${userDisplay(group.user_name, group.user_id)}</div></div>
    <div class="detail-row"><div class="detail-label">摘要</div><div class="detail-value"><strong>${escapeHtml(group.summary || '')}</strong></div></div>
    <div class="detail-row"><div class="detail-label">事实数</div><div class="detail-value">${facts.length}</div></div>
    <div class="detail-row"><div class="detail-label">时间</div><div class="detail-value">${formatTime(group.created_at)}</div></div>
    <hr style="border:none;border-top:1px solid #eee;margin:12px 0">
    <div style="font-weight:600;margin-bottom:8px">事实列表</div>
    ${factsHtml}
    <hr style="border:none;border-top:1px solid #eee;margin:12px 0">
    <div class="detail-row"><div class="detail-label">来源消息</div><div class="detail-value"><pre style="margin:0;white-space:pre-wrap">${escapeHtml(group.message_content || '')}</pre></div></div>
  `;
  showModal('事实组详情', html);
}

async function deleteGroup(id) {
  if (!confirm('确定要删除这个事实组及其所有事实吗？')) return;
  try {
    const group = currentFactGroups.find(g => g.id === id);
    if (group) {
      const facts = group.facts || [];
      for (const f of facts) {
        await api('/facts/' + f.id, { method: 'DELETE' });
      }
    }
    showToast('已删除', 'success');
    renderFacts(1);
  } catch (e) {
    showToast('删除失败: ' + e.message, 'error');
  }
}

// ============================================
// 操作日志（含分类筛选、统计、分页、搜索）
// ============================================
async function renderLogs(page, limit) {
  limit = limit || 20;
  try {
    const params = new URLSearchParams({ page: page || 1, limit: limit });
    if (logsFilter.status) params.set('status', logsFilter.status);
    if (logsFilter.category) params.set('category', logsFilter.category);
    if (logsFilter.keyword) params.set('keyword', logsFilter.keyword);

    const [res, stats] = await Promise.all([
      api('/logs?' + params.toString()),
      api('/logs/statistics')
    ]);
    const data = res.data || [];

    let html = `
      <div class="stats-grid">
        <div class="stat-card"><div class="label">总日志数</div><div class="value">${stats.total}</div></div>
        <div class="stat-card"><div class="label">成功</div><div class="value success">${stats.success}</div></div>
        <div class="stat-card"><div class="label">失败</div><div class="value ${stats.failed > 0 ? 'danger' : ''}">${stats.failed}</div></div>
        <div class="stat-card"><div class="label">消息</div><div class="value">${stats.message}</div></div>
        <div class="stat-card"><div class="label">AI</div><div class="value">${stats.ai}</div></div>
        <div class="stat-card"><div class="label">事实提取</div><div class="value">${stats.fact}</div></div>
        <div class="stat-card"><div class="label">认证</div><div class="value">${stats.auth}</div></div>
        <div class="stat-card"><div class="label">系统</div><div class="value">${stats.system}</div></div>
      </div>

      <div class="filter-bar">
        <input type="text" placeholder="搜索消息或用户..." value="${escapeHtml(logsFilter.keyword)}" 
               oninput="logsFilter.keyword=this.value" 
               onkeydown="if(event.key==='Enter') renderLogs(1)">
        <select onchange="logsFilter.category=this.value;renderLogs(1)">
          <option value="">全部分类</option>
          <option value="message" ${logsFilter.category==='message'?'selected':''}>消息</option>
          <option value="ai" ${logsFilter.category==='ai'?'selected':''}>AI</option>
          <option value="fact" ${logsFilter.category==='fact'?'selected':''}>事实提取</option>
          <option value="auth" ${logsFilter.category==='auth'?'selected':''}>认证</option>
          <option value="user" ${logsFilter.category==='user'?'selected':''}>用户</option>
          <option value="system" ${logsFilter.category==='system'?'selected':''}>系统</option>
        </select>
        <select onchange="logsFilter.status=this.value;renderLogs(1)">
          <option value="">全部状态</option>
          <option value="success" ${logsFilter.status==='success'?'selected':''}>成功</option>
          <option value="failed" ${logsFilter.status==='failed'?'selected':''}>失败</option>
          <option value="info" ${logsFilter.status==='info'?'selected':''}>信息</option>
        </select>
        <select onchange="renderLogs(1, parseInt(this.value))">
          ${pageSizeOptions.map(s => `<option value="${s}" ${s===limit?'selected':''}>${s}条/页</option>`).join('')}
        </select>
        <button class="btn btn-sm" onclick="renderLogs(1)">搜索</button>
      </div>
    `;

    if (data.length === 0) {
      html += '<div class="empty">暂无操作日志</div>';
    } else {
      html += '<div class="table-wrap"><table><thead><tr>';
      html += '<th>序号</th><th>时间</th><th>分类</th><th>用户</th><th>操作类型</th><th>目标表</th><th>状态</th><th>消息</th><th>耗时</th>';
      html += '</tr></thead><tbody>';
      const startIdx = (page - 1) * limit + 1;
      for (let i = 0; i < data.length; i++) {
        const l = data[i];
        const idx = startIdx + i;
        html += '<tr>';
        html += '<td style="text-align:center;width:60px">' + idx + '</td>';
        html += '<td style="white-space:nowrap">' + formatTime(l.created_at) + '</td>';
        html += '<td><span class="badge badge-info">' + escapeHtml(l.category || '-') + '</span></td>';
        html += '<td>' + userDisplay(l.user_name, l.user_id) + '</td>';
        html += '<td>' + escapeHtml(l.operation_type_display || l.operation_type) + '</td>';
        html += '<td>' + escapeHtml(l.target_table) + '</td>';
        html += '<td>' + statusBadge(l.status) + '</td>';
        html += '<td class="content-cell" title="' + escapeHtml(l.message) + '">' + escapeHtml(l.message) + '</td>';
        html += '<td>' + (l.duration_ms ? l.duration_ms + 'ms' : '-') + '</td>';
        html += '</tr>';
      }
      html += '</tbody></table></div>';
      html += paginationHtml(res.total || data.length, page, limit, 'renderLogs');
    }

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

// ============================================
// AI 调用日志
// ============================================
const callTypeNames = {
  fact_extraction: '事实提取',
  intent_detection: '意图检测',
  timeline_generation: '时间线生成',
  chat: '聊天对话',
  other: '其他',
};

async function renderAiLogs(page, limit) {
  limit = limit || 20;
  try {
    const params = new URLSearchParams({ page: page || 1, limit: limit });
    if (aiLogsFilter.status) params.set('status', aiLogsFilter.status);
    if (aiLogsFilter.call_type) params.set('call_type', aiLogsFilter.call_type);
    if (aiLogsFilter.keyword) params.set('keyword', aiLogsFilter.keyword);

    const [res, stats] = await Promise.all([
      api('/ai-logs?' + params.toString()),
      api('/ai-logs/statistics')
    ]);
    const data = res.data || [];

    let html = `
      <div class="stats-grid">
        <div class="stat-card"><div class="label">总调用次数</div><div class="value">${stats.total}</div></div>
        <div class="stat-card"><div class="label">成功</div><div class="value success">${stats.success}</div></div>
        <div class="stat-card"><div class="label">失败</div><div class="value ${stats.failed > 0 ? 'danger' : ''}">${stats.failed}</div></div>
        <div class="stat-card"><div class="label">事实提取</div><div class="value">${stats.fact_extraction}</div></div>
        <div class="stat-card"><div class="label">意图检测</div><div class="value">${stats.intent_detection}</div></div>
        <div class="stat-card"><div class="label">时间线生成</div><div class="value">${stats.timeline_generation || 0}</div></div>
        <div class="stat-card"><div class="label">聊天对话</div><div class="value">${stats.chat}</div></div>
        <div class="stat-card"><div class="label">总Token消耗</div><div class="value">${stats.total_tokens}</div></div>
        <div class="stat-card"><div class="label">总费用</div><div class="value" style="color:#fa541c">${stats.total_cost_display || '¥0.00'}</div></div>
      </div>

      <div class="stats-grid" style="grid-template-columns: repeat(4, 1fr); margin-top: 12px;">
        <div class="stat-card"><div class="label">输入 Token (Prompt)</div><div class="value">${stats.prompt_tokens}</div></div>
        <div class="stat-card"><div class="label">输出 Token (Completion)</div><div class="value">${stats.completion_tokens}</div></div>
        <div class="stat-card"><div class="label">平均响应时间</div><div class="value">${stats.avg_latency_ms || 0}ms</div></div>
        <div class="stat-card"><div class="label">平均每次费用</div><div class="value" style="color:#fa541c">${stats.avg_cost_display || '¥0.00'}</div></div>
      </div>

      <div class="filter-bar">
        <input type="text" placeholder="搜索内容..." value="${escapeHtml(aiLogsFilter.keyword)}" 
               oninput="aiLogsFilter.keyword=this.value" 
               onkeydown="if(event.key==='Enter') renderAiLogs(1)">
        <select onchange="aiLogsFilter.call_type=this.value;renderAiLogs(1)">
          <option value="">全部类型</option>
          <option value="fact_extraction" ${aiLogsFilter.call_type==='fact_extraction'?'selected':''}>事实提取</option>
          <option value="intent_detection" ${aiLogsFilter.call_type==='intent_detection'?'selected':''}>意图检测</option>
          <option value="timeline_generation" ${aiLogsFilter.call_type==='timeline_generation'?'selected':''}>时间线生成</option>
          <option value="chat" ${aiLogsFilter.call_type==='chat'?'selected':''}>聊天对话</option>
        </select>
        <select onchange="aiLogsFilter.status=this.value;renderAiLogs(1)">
          <option value="">全部状态</option>
          <option value="success" ${aiLogsFilter.status==='success'?'selected':''}>成功</option>
          <option value="failed" ${aiLogsFilter.status==='failed'?'selected':''}>失败</option>
        </select>
        <select onchange="renderAiLogs(1, parseInt(this.value))">
          ${pageSizeOptions.map(s => `<option value="${s}" ${s===limit?'selected':''}>${s}条/页</option>`).join('')}
        </select>
        <button class="btn btn-sm" onclick="renderAiLogs(1)">搜索</button>
      </div>
    `;

    if (data.length === 0) {
      html += '<div class="empty">暂无AI调用日志</div>';
    } else {
      html += '<div class="table-wrap"><table><thead><tr>';
      html += '<th>序号</th><th>时间</th><th>调用类型</th><th>用户</th><th>模型</th><th>状态</th><th>输入Token</th><th>输出Token</th><th>总Token</th><th>费用</th><th>耗时</th>';
      html += '</tr></thead><tbody>';
      const startIdx = (page - 1) * limit + 1;
      for (let i = 0; i < data.length; i++) {
        const l = data[i];
        const idx = startIdx + i;
        const typeName = callTypeNames[l.call_type] || l.call_type;
        const typeBadgeClass = l.call_type === 'chat' ? 'badge-primary' : 
                               l.call_type === 'fact_extraction' ? 'badge-info' : 'badge-success';
        html += '<tr style="cursor:pointer" onclick="showAiLogDetail(' + i + ')">';
        html += '<td style="text-align:center;width:60px">' + idx + '</td>';
        html += '<td style="white-space:nowrap">' + formatTime(l.created_at) + '</td>';
        html += '<td><span class="badge ' + typeBadgeClass + '">' + escapeHtml(typeName) + '</span></td>';
        html += '<td>' + userDisplay(l.user_name, l.user_id) + '</td>';
        html += '<td>' + escapeHtml(l.model || '-') + '</td>';
        html += '<td>' + statusBadge(l.status) + '</td>';
        html += '<td style="text-align:right">' + (l.prompt_tokens || 0) + '</td>';
        html += '<td style="text-align:right">' + (l.completion_tokens || 0) + '</td>';
        html += '<td style="text-align:right;font-weight:600">' + (l.total_tokens || 0) + '</td>';
        html += '<td style="text-align:right;color:#fa541c;font-weight:600">' + (l.cost_display || '¥0.00') + '</td>';
        html += '<td>' + (l.latency_ms ? l.latency_ms + 'ms' : '-') + '</td>';
        html += '</tr>';
      }
      html += '</tbody></table></div>';
      html += paginationHtml(res.total || data.length, page, limit, 'renderAiLogs');
      currentAiLogs = data;
    }

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

let currentAiLogs = [];

function showAiLogDetail(index) {
  const l = currentAiLogs[index];
  if (!l) return;
  
  const typeName = callTypeNames[l.call_type] || l.call_type;
  const inputCost = l.input_price && l.prompt_tokens ? (l.prompt_tokens / 1000000 * l.input_price) : 0;
  const outputCost = l.output_price && l.completion_tokens ? (l.completion_tokens / 1000000 * l.output_price) : 0;
  
  let html = `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px">
      <div><strong>调用类型：</strong>${escapeHtml(typeName)}</div>
      <div><strong>模型：</strong>${escapeHtml(l.model || '-')}</div>
      <div><strong>状态：</strong>${statusBadge(l.status)}</div>
      <div><strong>用户：</strong>${userDisplay(l.user_name, l.user_id)}</div>
      <div><strong>输入Token：</strong>${l.prompt_tokens || 0}</div>
      <div><strong>输出Token：</strong>${l.completion_tokens || 0}</div>
      <div><strong>总Token：</strong><span style="font-weight:600">${l.total_tokens || 0}</span></div>
      <div><strong>耗时：</strong>${l.latency_ms ? l.latency_ms + 'ms' : '-'}</div>
      <div><strong>温度：</strong>${l.temperature ?? '-'}</div>
      <div><strong>调用时间：</strong>${formatTime(l.created_at)}</div>
    </div>

    <div style="background:#fff7e6;border:1px solid #ffd591;border-radius:8px;padding:16px;margin-bottom:16px">
      <div style="font-weight:600;margin-bottom:12px;color:#fa541c">💰 费用明细</div>
      <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px">
        <div>
          <div style="color:#999;font-size:12px">输入费用</div>
          <div style="font-weight:600;color:#fa541c">¥${inputCost.toFixed(6)}</div>
          <div style="color:#999;font-size:11px">${l.prompt_tokens || 0} tokens × ¥${(l.input_price || 0)}/百万</div>
        </div>
        <div>
          <div style="color:#999;font-size:12px">输出费用</div>
          <div style="font-weight:600;color:#fa541c">¥${outputCost.toFixed(6)}</div>
          <div style="color:#999;font-size:11px">${l.completion_tokens || 0} tokens × ¥${(l.output_price || 0)}/百万</div>
        </div>
        <div>
          <div style="color:#999;font-size:12px">总费用</div>
          <div style="font-weight:700;color:#fa541c;font-size:16px">${l.cost_display || '¥0.00'}</div>
          <div style="color:#999;font-size:11px">${l.model || '-'}</div>
        </div>
      </div>
    </div>
  `;
  
  if (l.prompt) {
    html += `<div style="margin-bottom:12px"><strong>用户输入：</strong></div>
             <div class="code-block">${escapeHtml(l.prompt)}</div>`;
  }
  
  if (l.response) {
    html += `<div style="margin-top:12px;margin-bottom:12px"><strong>AI响应：</strong></div>
             <div class="code-block">${escapeHtml(l.response)}</div>`;
  }
  
  if (l.error_message) {
    html += `<div style="margin-top:12px;margin-bottom:12px"><strong>错误信息：</strong></div>
             <div class="code-block" style="background:#fef2f2;color:#dc2626">${escapeHtml(l.error_message)}</div>`;
  }
  
  if (l.system_prompt_preview) {
    html += `<div style="margin-top:12px;margin-bottom:12px"><strong>系统提示词预览：</strong></div>
             <div class="code-block" style="max-height:150px;overflow:auto;opacity:0.7">${escapeHtml(l.system_prompt_preview)}</div>`;
  }
  
  openModal('AI 调用详情', html);
}

// ============================================
// 数据检查
// ============================================
async function renderCheck() {
  try {
    const d = await api('/check');
    let html = `
      <div class="stats-grid">
        <div class="stat-card"><div class="label">用户消息总数</div><div class="value">${d.totalMessages}</div></div>
        <div class="stat-card"><div class="label">提取事实总数</div><div class="value success">${d.totalFacts}</div></div>
        <div class="stat-card"><div class="label">发现问题数</div><div class="value ${d.issueCount > 0 ? 'danger' : 'success'}">${d.issueCount}</div></div>
      </div>
    `;

    if (d.issueCount > 0) {
      html += '<div class="check-section">';
      html += '<h3>问题列表</h3>';
      html += '<div style="margin-bottom:12px"><button class="btn btn-success" onclick="fixData()">一键修复全部</button></div>';
      for (const issue of d.issues) {
        html += '<div class="issue-item">';
        html += '<span class="badge badge-error">' + escapeHtml(issue.type) + '</span>';
        html += '<span style="flex:1">' + escapeHtml(issue.content) + '...</span>';
        html += '<span style="color:var(--text-tertiary);font-size:12px">' + escapeHtml(issue.issue) + '</span>';
        html += '<button class="btn btn-sm" onclick="reextract(\'' + issue.message_id + '\')">重新提取</button>';
        html += '</div>';
      }
      html += '</div>';
    } else {
      html += '<div class="check-section"><h3>数据一致性检查</h3><p style="color:var(--success);padding:12px 0">所有数据一致，没有发现问题</p></div>';
    }

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">检查失败: ' + escapeHtml(e.message) + '</div>';
  }
}

async function fixData() {
  if (!confirm('确定要修复所有数据不一致问题吗？')) return;
  try {
    const result = await apiPost('/fix', { action: 'fix_extracted' });
    showToast('已修复 ' + result.fixed + ' 条数据', 'success');
    renderCheck();
  } catch (e) {
    showToast('修复失败: ' + e.message, 'error');
  }
}

// ============================================
// 用户管理（动态列、分页、搜索、序号）
// ============================================
async function renderUsers(page, limit) {
  limit = limit || 20;
  try {
    const params = new URLSearchParams({ page: page || 1, limit: limit });
    if (usersFilter.keyword) params.set('keyword', usersFilter.keyword);

    const res = await api('/users?' + params.toString());
    const data = res.data || [];

    let html = `
      <div class="filter-bar">
        <input type="text" placeholder="搜索用户名或邮箱..." value="${escapeHtml(usersFilter.keyword)}" 
               oninput="usersFilter.keyword=this.value" 
               onkeydown="if(event.key==='Enter') renderUsers(1)">
        <select onchange="renderUsers(1, parseInt(this.value))">
          ${pageSizeOptions.map(s => `<option value="${s}" ${s===limit?'selected':''}>${s}条/页</option>`).join('')}
        </select>
        <button class="btn btn-sm" onclick="renderUsers(1)">搜索</button>
        <button class="btn btn-sm btn-outline" onclick="refreshUserCache()">刷新用户缓存</button>
      </div>
    `;

    if (data.length === 0) {
      html += '<div class="empty">暂无用户</div>';
      document.getElementById('page-content').innerHTML = html;
      return;
    }

    const allKeys = new Set();
    for (const u of data) {
      for (const key of Object.keys(u)) {
        allKeys.add(key);
      }
    }
    const columns = Array.from(allKeys);

    const priorityCols = ['username', 'email', 'bio', 'created_at', 'id', 'birthday'];
    const sortedCols = columns.sort((a, b) => {
      const ai = priorityCols.indexOf(a);
      const bi = priorityCols.indexOf(b);
      if (ai !== -1 && bi !== -1) return ai - bi;
      if (ai !== -1) return -1;
      if (bi !== -1) return 1;
      return a.localeCompare(b);
    });

    const timeCols = new Set(['created_at', 'updated_at', 'last_sign_in_at', 'confirmed_at']);

    html += '<div class="table-wrap" style="overflow-x:auto"><table><thead><tr>';
    html += '<th>序号</th>';
    for (const col of sortedCols) {
      html += '<th>' + escapeHtml(col) + '</th>';
    }
    html += '</tr></thead><tbody>';
    const startIdx = (page - 1) * limit + 1;
    for (let i = 0; i < data.length; i++) {
      const u = data[i];
      const idx = startIdx + i;
      html += '<tr>';
      html += '<td style="text-align:center;width:60px">' + idx + '</td>';
      for (const col of sortedCols) {
        const val = u[col];
        if (col === 'id') {
          html += '<td class="id-cell" title="' + escapeHtml(val) + '">' + escapeHtml(val) + '</td>';
        } else if (timeCols.has(col) && val) {
          html += '<td style="white-space:nowrap">' + formatTime(val) + '</td>';
        } else if (val != null && typeof val === 'string' && val.length > 50) {
          html += '<td class="content-cell" title="' + escapeHtml(val) + '">' + escapeHtml(val) + '</td>';
        } else {
          html += '<td>' + (val != null ? escapeHtml(String(val)) : '-') + '</td>';
        }
      }
      html += '</tr>';
    }
    html += '</tbody></table></div>';
    html += paginationHtml(res.total || data.length, page, limit, 'renderUsers');

    document.getElementById('page-content').innerHTML = html;
  } catch (e) {
    document.getElementById('page-content').innerHTML = '<div class="empty">加载失败: ' + escapeHtml(e.message) + '</div>';
  }
}

async function refreshUserCache() {
  try {
    await apiPost('/users/refresh', {});
    showToast('用户缓存已刷新', 'success');
  } catch (e) {
    showToast('刷新失败: ' + e.message, 'error');
  }
}

// ============================================
// 分页（增强版：支持页码跳转、总条数、禁用状态）
// ============================================
function paginationHtml(total, page, limit, renderFn) {
  const pages = Math.ceil(total / limit) || 1;
  if (pages <= 1) return '';
  
  let html = '<div class="pagination">';
  html += '<button class="btn btn-sm btn-outline" onclick="' + renderFn + '(' + (page - 1) + ')" ' + (page <= 1 ? 'disabled' : '') + '>上一页</button>';
  
  const maxVisible = 5;
  let start = Math.max(1, page - Math.floor(maxVisible / 2));
  let end = Math.min(pages, start + maxVisible - 1);
  if (end - start < maxVisible - 1) start = Math.max(1, end - maxVisible + 1);
  
  for (let p = start; p <= end; p++) {
    if (p === page) {
      html += '<span class="page-current">' + p + '</span>';
    } else {
      html += '<button class="btn btn-sm btn-outline" onclick="' + renderFn + '(' + p + ')">' + p + '</button>';
    }
  }
  
  html += '<button class="btn btn-sm btn-outline" onclick="' + renderFn + '(' + (page + 1) + ')" ' + (page >= pages ? 'disabled' : '') + '>下一页</button>';
  html += '<span style="margin-left:12px;font-size:13px;color:var(--text-tertiary)">共 ' + total + ' 条</span>';
  
  html += '<div style="margin-left:16px;display:flex;align-items:center;gap:8px">';
  html += '<span style="font-size:13px;color:var(--text-tertiary)">跳转到:</span>';
  html += '<input type="number" min="1" max="' + pages + '" value="' + page + '" ' +
          'onkeydown="if(event.key===\'Enter\'){' + renderFn + '(parseInt(this.value));}" ' +
          'style="width:50px;padding:2px 6px;border:1px solid var(--border);border-radius:4px;font-size:13px">';
  html += '<button class="btn btn-sm btn-outline" onclick="' + renderFn + '(parseInt(this.previousElementSibling.value))">跳转</button>';
  html += '</div>';
  
  html += '</div>';
  return html;
}

// ============================================
// 初始化
// ============================================
async function init() {
  await loadConfig();

  if (authUser && supabaseConfig) {
    showAdmin();
  } else {
    showLogin();
  }

  document.getElementById('login-password').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') doLogin();
  });
  document.getElementById('login-email').addEventListener('keypress', (e) => {
    if (e.key === 'Enter') document.getElementById('login-password').focus();
  });
}

document.querySelectorAll('.nav-item').forEach(el => {
  el.addEventListener('click', () => navigate(el.dataset.page));
});

document.getElementById('modal-overlay').addEventListener('click', (e) => {
  if (e.target.id === 'modal-overlay') closeModal();
});

init();
