# Development Insights Setup Guide

This guide explains how to enable AI-powered student analysis in Maria's Notebook using Claude.

## What You'll Get

When configured, the "Development Insights" feature will:
- Analyze student notes, practice sessions, and work completions
- Generate detailed progress reports
- Identify strengths and areas for growth
- Recommend next lessons and interventions
- Create parent-friendly summaries

## Quick Setup (5 minutes)

### Step 1: Get an Anthropic API Key

1. Visit **https://console.anthropic.com/**
2. Sign up for a free account
3. Navigate to **"API Keys"** in the sidebar
4. Click **"Create Key"**
5. Copy the key (it starts with `sk-ant-`)

**Free credits:** New accounts get $5 in free credits (~250-500 student analyses)

### Step 2: Add API Key to Maria's Notebook

1. Open Maria's Notebook
2. Go to **Settings** (in the app menu or preferences)
3. Find **"AI Settings"** or **"API Key Settings"**
4. Paste your API key
5. Click **"Save API Key"**

### Step 3: Use Development Insights

1. Navigate to any student
2. Click the **Progress** tab
3. Click **"Development Insights"** (purple card with brain icon at the top)
4. Click **"Generate New Analysis"**
5. Wait 10-30 seconds for Claude to analyze the data

That's it! You'll get a detailed AI-generated analysis of the student's progress.

## Cost Information

### Pricing (as of 2026)
- **Claude 3.5 Sonnet:** $3 per million input tokens, $15 per million output tokens
- **Typical analysis:** 2,000-4,000 input tokens + 1,000-2,000 output tokens
- **Per analysis:** ~$0.01-0.02 (1-2 cents)

### Free Tier
- New accounts: $5 credit
- Approximately 250-500 student analyses included
- Check usage at: https://console.anthropic.com/

### Cost Examples
- Analyzing 10 students once: ~$0.10-0.20
- Weekly analyses for 25 students: ~$0.25-0.50/week
- Monthly reports for entire class: ~$1-2/month

## Privacy & Security

- ✅ API key stored securely on your device only
- ✅ Data sent directly to Anthropic (Claude's makers)
- ✅ No third-party servers involved
- ✅ Data used only for your analysis, not stored by Anthropic
- ✅ You control when analyses are generated

## What Gets Analyzed?

When you generate an analysis, the app sends:
- Student profile (name, age, level)
- Notes from the selected time period (7-90 days)
- Practice session records (quality, independence, flags)
- Work completion records
- Aggregate metrics

Claude returns:
- Overall progress narrative
- Key strengths (3-5 items)
- Areas for growth (2-3 items)
- Developmental milestones achieved
- Observed patterns and behavioral trends
- Social-emotional insights
- Recommended next lessons
- Intervention suggestions (if needed)

## Troubleshooting

### "No API key configured" error
1. Go to Settings → AI Settings
2. Enter your API key
3. Click Save

### "Invalid API key format" error
- Make sure the key starts with `sk-ant-`
- Check for extra spaces before/after the key
- Try creating a new key from console.anthropic.com

### "API error (401)" - Authentication failed
- Your API key may be incorrect
- Try creating a new key from console.anthropic.com
- Make sure you copied the entire key

### "API error (429)" - Rate limit exceeded
- You've hit API rate limits
- Wait a few minutes before trying again
- Consider upgrading your Anthropic plan if needed

### "API error (402)" - Payment required
- You've used all your free credits
- Add payment method at console.anthropic.com
- Or wait for credits to reset (if on a paid plan)

### Analysis seems generic or incorrect
- Make sure you have enough student notes (at least 5-10)
- Try a longer lookback period (30-60 days instead of 7 days)
- Verify your notes contain detailed observations

## Tips for Best Results

### Write Better Notes
- Be specific in your observations
- Include concrete examples
- Note both successes and challenges
- Record social-emotional observations

### Choose Appropriate Time Periods
- **7 days:** Recent snapshot, quick check-ins
- **30 days:** Balanced view, good for monthly reports
- **60-90 days:** Long-term trends, comprehensive reports

### Regular Analysis Schedule
- Weekly quick analyses (7-day lookback)
- Monthly comprehensive reports (30-day lookback)
- Quarterly progress reviews (90-day lookback)

## Features You Can Use

### Generate Analysis
Click "Generate New Analysis" to create a new development snapshot.

### Parent Summaries
Click "Share with Parents" to generate a parent-friendly version of the analysis you can email or print.

### Historical Tracking
View previous analyses to see progress over time. The app keeps all past snapshots.

### Mark as Reviewed
Mark analyses as reviewed to track which ones you've read.

## Getting Help

### Check API Status
Visit status.anthropic.com to see if there are any API issues.

### View API Usage
Log in to console.anthropic.com to see your API usage and costs.

### Contact Support
- For API issues: support@anthropic.com
- For app issues: Check the Maria's Notebook support channels

## Next Steps

1. **Test with one student** - Generate your first analysis to see how it works
2. **Review the results** - Check if the insights match your observations
3. **Adjust time periods** - Try different lookback periods
4. **Use parent summaries** - Generate a shareable summary
5. **Track progress** - Generate analyses regularly to see trends

---

**Ready to start?** Get your API key from https://console.anthropic.com/ and add it to Settings!
