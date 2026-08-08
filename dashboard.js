// AI Cost Hub - Dashboard Controller

document.addEventListener('DOMContentLoaded', () => {
    // API host (supports both direct server running and file:/// direct double-click)
    const API_BASE = window.location.protocol === 'file:' ? 'http://127.0.0.1:5333' : '';
    
    // Timeframe State
    let activeRange = 'day';

    // UI Elements - Core Metrics
    const todayCostText = document.getElementById('todayCost');
    const budgetLimitLabel = document.getElementById('budgetLimitLabel');
    const progressCircle = document.getElementById('progressCircle');
    const totalInputTokensText = document.getElementById('totalInputTokens');
    const totalOutputTokensText = document.getElementById('totalOutputTokens');
    const statusOrb = document.getElementById('statusOrb');
    const statusText = document.getElementById('statusText');
    
    // UI Elements - Navigation & Drawers
    const settingsDrawer = document.getElementById('settingsDrawer');
    const toggleSettingsBtn = document.getElementById('toggleSettingsBtn');
    const closeSettingsBtn = document.getElementById('closeSettingsBtn');
    
    // UI Elements - Trend Sparkline
    const trendPath = document.getElementById('trendPath');
    const trendArea = document.getElementById('trendArea');
    const sparklineDays = document.getElementById('sparklineDays');
    const trendAverageLabel = document.getElementById('trendAverage');

    // UI Elements - Timeframe Selector
    const tfDayBtn = document.getElementById('timeframe-day');
    const tfMonthBtn = document.getElementById('timeframe-month');
    const tfYearBtn = document.getElementById('timeframe-year');
    
    // UI Elements - Columns
    const providersList = document.getElementById('providersList');
    const modelsBreakdownChart = document.getElementById('modelsBreakdownChart');
    const activityTimeline = document.getElementById('activityTimeline');
    
    // UI Elements - Forms & Tables (Drawer)
    const configForm = document.getElementById('configForm');
    const dailyBudgetInput = document.getElementById('dailyBudgetInput');
    const overrideForm = document.getElementById('overrideForm');
    const overrideModel = document.getElementById('overrideModel');
    const overrideInputRate = document.getElementById('overrideInputRate');
    const overrideOutputRate = document.getElementById('overrideOutputRate');
    const overridesList = document.getElementById('overridesList');
    
    // UI Elements - Action Buttons
    const syncBtn = document.getElementById('syncBtn');
    const resetBtn = document.getElementById('resetBtn');

    // Providers styling configurations
    const providerConfig = {
        'OpenAI': { color: 'var(--color-openai)', glow: 'rgba(16, 185, 129, 0.25)', icon: '🟢' },
        'Anthropic': { color: 'var(--color-anthropic)', glow: 'rgba(139, 92, 246, 0.25)', icon: '🟣' },
        'Google Gemini': { color: 'var(--color-gemini)', glow: 'rgba(59, 130, 246, 0.25)', icon: '🔵' },
        'OpenRouter': { color: 'var(--color-openrouter)', glow: 'rgba(245, 158, 11, 0.25)', icon: '🟡' },
        'Claude Code': { color: 'var(--color-claudecode)', glow: 'rgba(236, 72, 153, 0.25)', icon: '🔴' }
    };

    // --- Control Drawer Handlers ---
    
    toggleSettingsBtn.addEventListener('click', () => {
        settingsDrawer.classList.add('active');
        fetchOverrides();
    });

    closeSettingsBtn.addEventListener('click', () => {
        settingsDrawer.classList.remove('active');
    });

    settingsDrawer.addEventListener('click', (e) => {
        if (e.target === settingsDrawer) {
            settingsDrawer.classList.remove('active');
        }
    });

    // --- Relative Time Helper ---
    
    function getRelativeTime(isoString) {
        try {
            const date = new Date(isoString);
            const now = new Date();
            const diffMs = now - date;
            const diffSec = Math.floor(diffMs / 1000);
            const diffMin = Math.floor(diffSec / 60);
            const diffHour = Math.floor(diffMin / 60);
            
            if (diffSec < 10) return 'Just now';
            if (diffSec < 60) return `${diffSec}s ago`;
            if (diffMin < 60) return `${diffMin}m ago`;
            if (diffHour < 24) return `${diffHour}h ago`;
            return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
        } catch (e) {
            return 'Recently';
        }
    }

    // --- Update Core Stats Dashboard ---
    
    async function updateDashboard() {
        try {
            const res = await fetch(`${API_BASE}/api/stats?range=${activeRange}`);
            if (!res.ok) throw new Error('API server returned error');
            const data = await res.json();
            
            const stats = data.today || { cost: 0.0, input_tokens: 0, output_tokens: 0 };
            const dailyBudget = parseFloat(data.config?.daily_budget || '5.00');
            
            let budget = dailyBudget;
            if (activeRange === 'month') {
                budget = dailyBudget * 30;
            } else if (activeRange === 'year') {
                budget = dailyBudget * 365;
            }
            
            // 1. Text Metrics
            todayCostText.textContent = stats.cost.toFixed(2);
            if (budgetLimitLabel) budgetLimitLabel.textContent = budget.toFixed(2);
            totalInputTokensText.textContent = stats.input_tokens.toLocaleString();
            totalOutputTokensText.textContent = stats.output_tokens.toLocaleString();
            
            // Update labels dynamically
            const spendPeriodLabel = document.getElementById('spendPeriodLabel');
            if (spendPeriodLabel) {
                spendPeriodLabel.textContent = activeRange === 'day' ? 'Spent Today' : (activeRange === 'month' ? 'Spent This Month' : 'Spent This Year');
            }
            const budgetPeriodLabel = document.getElementById('budgetPeriodLabel');
            if (budgetPeriodLabel) {
                budgetPeriodLabel.textContent = activeRange === 'day' ? 'daily' : (activeRange === 'month' ? 'monthly' : 'yearly');
            }
            const trendTitle = document.getElementById('trendTitle');
            if (trendTitle) {
                trendTitle.textContent = activeRange === 'day' ? 'Weekly Trend' : (activeRange === 'month' ? 'Monthly Trend' : 'Yearly Trend');
            }
            
            // 2. Radial Budget Gauge
            const circumference = 2 * Math.PI * 42; // r=42 -> 263.89
            const percentage = budget > 0 ? (stats.cost / budget) : 0;
            const offset = circumference - (Math.min(percentage, 1.0) * circumference);
            progressCircle.style.strokeDashoffset = offset;
            
            // Color grading and status orb states
            if (percentage >= 1.0) {
                progressCircle.style.stroke = 'var(--color-danger)';
                progressCircle.style.filter = 'drop-shadow(0 0 8px var(--color-danger-glow))';
                statusOrb.className = 'status-orb glowing-red';
                statusOrb.style.backgroundColor = 'var(--color-danger)';
                statusOrb.style.boxShadow = '0 0 10px var(--color-danger)';
                statusText.textContent = 'Quota Exceeded';
                statusText.style.color = 'var(--color-danger)';
            } else if (percentage >= 0.8) {
                progressCircle.style.stroke = 'var(--color-warning)';
                progressCircle.style.filter = 'drop-shadow(0 0 8px var(--color-warning-glow))';
                statusOrb.className = 'status-orb glowing-orange';
                statusOrb.style.backgroundColor = 'var(--color-warning)';
                statusOrb.style.boxShadow = '0 0 10px var(--color-warning)';
                statusText.textContent = 'Approaching Limit';
                statusText.style.color = 'var(--color-warning)';
            } else {
                progressCircle.style.stroke = 'var(--color-primary)';
                progressCircle.style.filter = 'drop-shadow(0 0 8px var(--color-primary-glow))';
                statusOrb.className = 'status-orb glowing-green';
                statusOrb.style.backgroundColor = 'var(--color-success)';
                statusOrb.style.boxShadow = '0 0 10px var(--color-success)';
                statusText.textContent = 'Active Monitoring';
                statusText.style.color = 'var(--text-muted)';
            }

            // 3. Render Sparkline Chart
            renderSparkline(data.trend || []);

            // 4. Render Provider Distributions
            renderProviders(data.providers || {}, budget);

            // 5. Render Model Share Bars
            renderModels(data.models || []);

            // 6. Render Live Timeline Stream
            renderTimeline(data.recent_logs || []);

        } catch (error) {
            console.error('Failed to update stats:', error);
            statusOrb.className = 'status-orb';
            statusOrb.style.backgroundColor = 'var(--text-muted)';
            statusOrb.style.boxShadow = 'none';
            statusText.textContent = 'Daemon Offline';
            statusText.style.color = 'var(--text-muted)';
            todayCostText.textContent = '?.??';
        }
    }

    // --- Render Sparkline Helper ---
    
    function renderSparkline(trend) {
        if (!trend || trend.length === 0) return;
        
        const width = 300;
        const height = 70;
        const padding = 6;
        
        // Find max cost to scale heights (default minimum peak of $0.10 for nice look)
        const maxCost = Math.max(0.10, ...trend.map(t => t.cost));
        
        // Generate coordinates
        const points = trend.map((t, index) => {
            const x = (index / (trend.length - 1)) * width;
            const y = height - ((t.cost / maxCost) * (height - 2 * padding)) - padding;
            return { x, y };
        });
        
        // Construct SVG line path (curved layout)
        let lineD = `M ${points[0].x} ${points[0].y}`;
        for (let i = 1; i < points.length; i++) {
            // Cubic bezier smoothing
            const cpX1 = points[i-1].x + (points[i].x - points[i-1].x) / 2;
            const cpY1 = points[i-1].y;
            const cpX2 = points[i-1].x + (points[i].x - points[i-1].x) / 2;
            const cpY2 = points[i].y;
            lineD += ` C ${cpX1} ${cpY1}, ${cpX2} ${cpY2}, ${points[i].x} ${points[i].y}`;
        }
        
        // Construct filled area path
        const areaD = `${lineD} L ${width} ${height} L 0 ${height} Z`;
        
        trendPath.setAttribute('d', lineD);
        trendArea.setAttribute('d', areaD);
        
        // Update days label text (filter to avoid cluttering in large lists)
        sparklineDays.innerHTML = '';
        trend.forEach((t, index) => {
            const span = document.createElement('span');
            if (trend.length <= 15 || index % 5 === 0 || index === trend.length - 1) {
                span.textContent = t.day;
            } else {
                span.textContent = '';
            }
            sparklineDays.appendChild(span);
        });
        
        // Calculate average spend
        const sum = trend.reduce((acc, t) => acc + t.cost, 0);
        const avg = sum / trend.length;
        if (trendAverageLabel) {
            trendAverageLabel.textContent = `$${avg.toFixed(2)} avg / ${activeRange === 'year' ? 'month' : 'day'}`;
        }
    }

    // --- Render Providers Helper ---
    
    function renderProviders(providers, budget) {
        providersList.innerHTML = '';
        
        // Sort providers by spend descending
        const sorted = Object.entries(providers).sort((a, b) => b[1].cost - a[1].cost);
        
        sorted.forEach(([name, metrics]) => {
            const conf = providerConfig[name] || { color: 'var(--text-muted)', glow: 'none', icon: '⚙️' };
            const row = document.createElement('div');
            row.className = 'provider-row-item';
            
            row.innerHTML = `
                <div class="prov-info">
                    <span class="prov-indicator" style="background-color: ${conf.color}; box-shadow: 0 0 8px ${conf.color};"></span>
                    <span class="prov-name">${conf.icon} ${name}</span>
                </div>
                <div class="prov-right">
                    <span class="prov-cost">$${metrics.cost.toFixed(3)}</span>
                    <div class="prov-subtext">${metrics.input.toLocaleString()} in / ${metrics.output.toLocaleString()} out</div>
                </div>
            `;
            providersList.appendChild(row);
        });
    }

    // --- Render Models Share Bars Helper ---
    
    function renderModels(models) {
        modelsBreakdownChart.innerHTML = '';
        
        if (models.length === 0) {
            modelsBreakdownChart.innerHTML = '<p style="color: var(--text-muted); font-size: 0.8rem; text-align: center; margin-top: 2rem;">No API calls logged today.</p>';
            return;
        }
        
        const totalCost = models.reduce((acc, m) => acc + m.cost, 0);
        
        models.forEach((m) => {
            const percentage = totalCost > 0 ? (m.cost / totalCost) * 100 : 0;
            const barItem = document.createElement('div');
            barItem.className = 'model-bar-item';
            
            // Map colors to matching providers
            const conf = providerConfig[m.provider] || { color: 'var(--color-primary)' };
            
            barItem.innerHTML = `
                <div class="model-bar-text">
                    <span class="model">${m.model}</span>
                    <span class="cost">$${m.cost.toFixed(3)} (${percentage.toFixed(0)}%)</span>
                </div>
                <div class="bar-track">
                    <div class="bar-fill" style="width: ${percentage.toFixed(1)}%; background-color: ${conf.color}; box-shadow: 0 0 6px ${conf.color}90;"></div>
                </div>
            `;
            modelsBreakdownChart.appendChild(barItem);
        });
    }

    // --- Render Live Timeline Helper ---
    
    function renderTimeline(logs) {
        activityTimeline.innerHTML = '';
        
        if (logs.length === 0) {
            activityTimeline.innerHTML = '<p style="color: var(--text-muted); font-size: 0.8rem; padding: 2rem 0; text-align: center;">No recent transactions.</p>';
            return;
        }
        
        logs.forEach((log) => {
            const node = document.createElement('div');
            node.className = 'timeline-node';
            
            // Map provider color accent
            const conf = providerConfig[log.provider] || { color: 'var(--color-primary)' };
            node.style.setProperty('--color-primary', conf.color);
            
            const timeLabel = getRelativeTime(log.timestamp);
            const detailStr = log.input_tokens > 0 
                ? `${log.input_tokens.toLocaleString()} in / ${log.output_tokens.toLocaleString()} out` 
                : `${log.source}`;
                
            node.innerHTML = `
                <div class="node-card">
                    <div class="node-meta">
                        <span class="prov-pill">${log.provider}</span>
                        <span class="time">${timeLabel}</span>
                    </div>
                    <div class="node-model">${log.model}</div>
                    <div class="node-details">
                        <span class="node-tokens">${detailStr}</span>
                        <span class="node-cost">$${log.cost.toFixed(4)}</span>
                    </div>
                </div>
            `;
            activityTimeline.appendChild(node);
        });
    }

    // --- Fetch Overrides (Drawer Panel) ---
    
    async function fetchOverrides() {
        try {
            const res = await fetch(`${API_BASE}/api/config`);
            const data = await res.json();
            
            // Fill budget input
            dailyBudgetInput.value = data.config?.daily_budget || '5.00';
            
            // Fill overrides table
            overridesList.innerHTML = '';
            const overrides = data.overrides || [];
            
            if (overrides.length === 0) {
                overridesList.innerHTML = '<tr><td colspan="4" style="color: var(--text-muted); text-align: center; padding: 1rem 0;">No active overrides.</td></tr>';
                return;
            }
            
            overrides.forEach(row => {
                const tr = document.createElement('tr');
                tr.innerHTML = `
                    <td style="font-weight: 600; font-family: var(--font-body);">${row.model}</td>
                    <td>$${row.input_cost_per_m.toFixed(2)}</td>
                    <td>$${row.output_cost_per_m.toFixed(2)}</td>
                    <td style="text-align: right;">
                        <button class="btn-delete-override" data-model="${row.model}">✕</button>
                    </td>
                `;
                overridesList.appendChild(tr);
            });
            
            // Register delete buttons click
            document.querySelectorAll('.btn-delete-override').forEach(btn => {
                btn.addEventListener('click', async (e) => {
                    const model = e.target.getAttribute('data-model');
                    if (confirm(`Remove pricing override for ${model}?`)) {
                        await deleteOverride(model);
                    }
                });
            });
        } catch (error) {
            console.error('Failed to load overrides config:', error);
        }
    }

    // --- Save Budget Handler ---
    
    configForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const value = parseFloat(dailyBudgetInput.value);
        if (isNaN(value) || value < 0.1) return;
        
        try {
            const res = await fetch(`${API_BASE}/api/config`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ daily_budget: value.toFixed(2) })
            });
            if (res.ok) {
                alert('Daily budget limit saved successfully!');
                updateDashboard();
            } else {
                alert('Error saving budget config.');
            }
        } catch (error) {
            console.error('Failed to save budget:', error);
            alert('Failed to connect to daemon server.');
        }
    });

    // --- Register Override Handler ---
    
    overrideForm.addEventListener('submit', async (e) => {
        e.preventDefault();
        const model = overrideModel.value.trim();
        const inputRate = parseFloat(overrideInputRate.value);
        const outputRate = parseFloat(overrideOutputRate.value);
        
        if (!model || isNaN(inputRate) || isNaN(outputRate)) return;
        
        try {
            const res = await fetch(`${API_BASE}/api/config`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    override_model: model,
                    input_cost_per_m: inputRate,
                    output_cost_per_m: outputRate
                })
            });
            if (res.ok) {
                overrideModel.value = '';
                overrideInputRate.value = '';
                overrideOutputRate.value = '';
                fetchOverrides();
                updateDashboard();
            } else {
                alert('Failed to register model override.');
            }
        } catch (error) {
            console.error('Override registration failed:', error);
            alert('Failed to save override.');
        }
    });

    // --- Delete Override Helper ---
    
    async function deleteOverride(model) {
        try {
            const res = await fetch(`${API_BASE}/api/config`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ delete_override: model })
            });
            if (res.ok) {
                fetchOverrides();
                updateDashboard();
            } else {
                alert('Failed to delete override.');
            }
        } catch (error) {
            console.error('Failed to delete override:', error);
        }
    }

    // --- Maintenance Actions Handler ---
    
    syncBtn.addEventListener('click', async () => {
        syncBtn.textContent = 'Syncing...';
        syncBtn.disabled = true;
        try {
            const res = await fetch(`${API_BASE}/api/sync`, { method: 'POST' });
            if (res.ok) {
                alert('Claude logs synced successfully!');
                updateDashboard();
            } else {
                alert('Sync failed.');
            }
        } catch (error) {
            console.error('Sync failed:', error);
            alert('Error contacting daemon.');
        } finally {
            syncBtn.textContent = '🔄 Sync Claude Logs';
            syncBtn.disabled = false;
        }
    });

    resetBtn.addEventListener('click', async () => {
        if (confirm("Are you sure you want to clear all data logs for today? This cannot be undone.")) {
            try {
                const res = await fetch(`${API_BASE}/api/reset`, { method: 'POST' });
                if (res.ok) {
                    alert('Today\'s cost stats cleared.');
                    updateDashboard();
                    fetchOverrides();
                } else {
                    alert('Reset failed.');
                }
            } catch (error) {
                console.error('Reset error:', error);
            }
        }
    });

    // --- Timeframe Listeners Setup ---
    
    function setupTimeframeListeners() {
        if (!tfDayBtn || !tfMonthBtn || !tfYearBtn) return;
        
        const buttons = [
            { btn: tfDayBtn, range: 'day' },
            { btn: tfMonthBtn, range: 'month' },
            { btn: tfYearBtn, range: 'year' }
        ];
        
        buttons.forEach(({ btn, range }) => {
            btn.addEventListener('click', () => {
                buttons.forEach(b => b.btn.classList.remove('active'));
                btn.classList.add('active');
                activeRange = range;
                updateDashboard();
            });
        });
    }

    // --- Initialization and Polling ---
    
    setupTimeframeListeners();
    updateDashboard();
    setInterval(updateDashboard, 3000);
});
