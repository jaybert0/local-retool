---
name: monthly-cloud-stability-report
description: Generates the Monthly Cloud Stability Report from Databricks data, publishes to Confluence, and notifies via Slack in #support-alerts.
schedule: "0 14 1 * *"
---

You are running the Monthly Cloud Stability Report pipeline. Execute the following steps in order.

---

## STEP 1 — QUERY DATABRICKS

Run this SQL query using the Databricks connector:

```sql
SELECT 
    c.casenumber,
    c.subject, 
    c.Contactemail, 
    c.id, 
    c.Origin, 
    c.plan_name_at_create__c, 
    c.outcome__c, 
    u.name, 
    c.first_solved_at__c,
    c.submitted_at__c,
    collect_list(struct(l.issue_url, l.issue_state_name, l.issue_title)) as linears,
    datediff(MINUTE, c.submitted_at__c, c.first_solved_at__c) / 60 as hours_to_close,
    c.time_to_first_retool_reply__c 
FROM production.polytomic_salesforce.case c
LEFT JOIN production.polytomic_salesforce.user u ON c.Ownerid = u.id
LEFT JOIN production.dbt_dim.dim_linear_attachments l ON c.id = l.sfdc_case_id
WHERE c.origin = 'Breakage Report'
    AND c.first_solved_at__c >= date_trunc('month', add_months(current_date(), -1))
    AND c.first_solved_at__c < date_trunc('month', current_date())
    AND c.outcome__c != 'Duplicate'
GROUP BY 
    c.id, c.casenumber, c.subject, c.Contactemail, c.Origin,
    c.plan_name_at_create__c, c.outcome__c, u.name,
    c.first_solved_at__c, c.submitted_at__c, c.time_to_first_retool_reply__c
ORDER BY c.first_solved_at__c DESC
```

If the query returns 0 rows: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Monthly Cloud Stability Report could not be generated — Databricks query returned no results for [month/year]. Please check the data source." Then stop.

---

## STEP 2 — GATHER INCIDENT CONTEXT FROM SLACK

Incident channels follow the naming pattern `inc-{number}-{slug}--{YYYY-MM-DD}` where the date is when the incident was declared. Use the Slack connector to find and read all incident channels that were active during the reporting month.

**2a. Search for incident channels**

Use `slack_search_channels` to search for channels matching the reporting month. Run two searches in parallel:
- Query: `inc- [YYYY-MM]` (e.g. `inc- 2026-04`) to find channels declared that month
- Query: the previous month's pattern as well (e.g. `inc- 2026-03`) to catch long-running incidents declared in the prior month that may still have been active and generating support cases in the reporting month

For each channel found, note its channel ID, full name, and declared date from the channel name.

**2b. Read each incident channel**

For each incident channel identified, read the full channel history using `slack_read_channel`. Paginate if needed. From each channel extract:
- Incident name and severity (from the Retool Bot topic — look for `Severity: sev1 / sev2 / sev3`)
- DRI name
- Timeline: when declared, when moved to monitoring, when resolved
- Root cause (look for engineering posts describing the cause — often from Jake Scott, Claire Lin, Stephan Pfistner, or whoever the DRI is)
- Mitigation and fix steps taken
- Whether a postmortem was scheduled or completed
- Any Linear ticket linked by the Retool Bot resolution message (format: `Updating linear.app/retool/issue/INC-XXXX`)
- Status page link if posted
- Any named customers significantly impacted (look for support owners posting customer names)

**2c. Build an incident reference table**

Compile a summary like this for use in Step 4:

| INC # | Severity | Channel | Declared | Resolved | Duration | Root Cause Summary | Linear | Status Page |
|---|---|---|---|---|---|---|---|---|

Keep this table in working memory — you will use it in Section 3 (Incident Clustering) and the incident narratives of the report.

---

## STEP 3 — FETCH PRIOR MONTH DATA FOR COMPARISON

**3a. Find last month's Confluence report**

Use `searchConfluenceUsingCql` in the SUP space to find the previous month's report:

```
title = "Cloud Stability Report — [Previous Month] [Year]" AND space.key = "SUP"
```

If a page is found, fetch its full content using `getConfluencePage`. Extract these metrics to use in Section 1 and Section 7 of the new report:
- Total cases reviewed
- Confirmed breakage rate (%)
- Critical breakage count
- Non-breakage / configuration-error rate (%)
- Number of unsolved breakages at month end
- Top incident cluster (name and case count)
- EPD team with the most confirmed breakages
- Linear ticket coverage (X of Y clusters)

If no prior month report exists, note "No prior month data available" and continue.

**3b. Store the comparison baseline**

Keep these prior-month figures in working memory — you will reference them in the blockquote in Section 1, the MoM narrative in Section 7, and the Executive Summary.

---

## STEP 4 — GENERATE THE REPORT

Using the Databricks data (Step 1), incident context (Step 2), and prior month baseline (Step 3), write a Cloud Stability Report for the previous calendar month.
The report preparer is always "Jay Lee, Cloud Stability Engineer."
Use the exact structure below.

**Important:** Do not guess at incident root causes or cluster descriptions. If a support case cluster maps to a declared incident from Step 2, use the actual incident data — root cause, DRI, timeline, fix, named customers — rather than inferring from truncated case subjects. A case cluster's "hours to close" may reflect incident duration, not support response speed; note this distinction where relevant.

---

### REPORT STRUCTURE:

# Cloud Stability Report — [Month] [Year]
**Prepared by:** Jay Lee, Cloud Stability Engineer
**Scope:** All Breakage Reports submitted in [Month] [Year]
**Total cases reviewed:** [total row count from query]

---

#### Executive Summary

Write 2–3 paragraphs covering:
- Total breakage reports and confirmed breakage rate
- The month's dominant incident themes — name declared incidents (INC-XXXX) by name where applicable, with severity and duration
- Any notable unresolved bugs or open breakages at month end
- A direct comparison to the prior month (case volume, confirmed breakage rate, critical count, dominant team) using the data from Step 3

---

#### 1. Outcome Breakdown

Create a table with columns: Outcome | Count | % of Total

Categorize each row by outcome__c into these buckets:
- Solved - Breakage
- Solved - Critical Breakage
- Solved - Non-Breakage
- Unsolved - Breakage
- Unsolved - Non-Breakage
- Unresolved - Customer Unresponsive
- Other (anything that doesn't fit above)

Below the table, state:
- Confirmed breakages = (Solved - Critical Breakage + Solved - Breakage + Unsolved - Breakage) / total
- Configuration/user error rate = (Solved - Non-Breakage + Unsolved - Non-Breakage) / total
- Add a blockquote with the prior month's confirmed breakage rate and non-breakage rate for direct comparison, using the values from Step 3

---

#### 2. Breakage by Product Area and EPD Team

Map each case's subject/product area to an EPD team using these rules:
- Hub, permissions, groups, audit logs, SSO, governance → Governance
- Connect, resources, connectors, databases, OAuth, Firebase, Firestore, Retool DB → Resources
- App Building, editor, components, queries, pages, tables, tabs → Apps Foundation or Apps Builder Experience (split based on whether it's infrastructure/query-layer vs UI/component-layer)
- Workflows, automations → Automations
- Assist → Assist

For cases that map to a declared incident from Step 2, use the incident's EPD team attribution directly rather than inferring from the case subject.

Only count confirmed breakages (Critical + Standard + Unsolved) in these tables.

Table 1 — By product area:
| Product Area | EPD Team | Breakages | Critical | % of Breakages |

Table 2 — By EPD team:
| EPD Team | Total | Critical | Standard | Unsolved |

Add a 2–3 sentence narrative below the tables noting which team led by volume vs. which had the most critical cases. Where a team's numbers are dominated by a single declared incident, say so explicitly.

---

#### 3. Incident Clustering

**First**, place each declared incident from Step 2 that had confirmed breakage cases as its own named cluster, with the INC number, severity, timeline, and Linear ticket from the incident channel.

**Then**, group any remaining cases that share the same root symptom (same subject pattern + same EPD team + overlapping dates) into additional clusters.

Table A — Multi-ticket clusters (2 or more cases with the same root cause):
| # | Incident | Cases | Severity | Date(s) | EPD Team | Linear |

For the Linear column: use the INC-XXXX ticket from the incident channel if one exists. Otherwise check the linears field. If neither exists, use "—".

Table B — Single-case incidents:
| # | Incident | Date | Severity | EPD Team |

Table C — Summary by EPD team:
| EPD Team | Incidents | Critical Cases | Notes |

Write a detailed narrative for each declared incident (from Step 2): describe the symptom, root cause, DRI, affected customers, timeline (declared → monitoring → resolved), fix deployed, postmortem status, and Linear ticket. For inferred clusters (no declared incident), describe the symptom, affected dates, resolution status, and any linked Linear ticket.

If any cluster remains unresolved, call it out explicitly with the Linear ticket number if one exists.

---

#### 4. Resolution Speed

Table: Outcome | Median Hours to Close | n

Calculate median from the hours_to_close field, grouped by outcome category.
Note: hours_to_close = datediff in minutes / 60 between submitted_at__c and first_solved_at__c.

If a cluster of cases has elevated hours_to_close because it maps to a long-running declared incident (not slow support response), note that explicitly below the table.

Below the table, list any breakages still unsolved at month end (outcome__c contains "Unsolved").

---

#### 5. Customer Tier and Plan

Table of confirmed breakages by plan_name_at_create__c:
| Plan | Breakages | % |

Note which plan tier is most affected and whether it's disproportionate relative to expected distribution. If a declared incident disproportionately hit a specific plan tier, say so.

---

#### 6. Engineering Escalations (Linear)

List all unique Linear tickets found across all sources: the linears field from Databricks AND the incident Linear tickets from Step 2. For each:
- Ticket ID and URL
- Title
- Current state
- Source (support case link vs. incident management ticket)
- Which cases or incidents it covers

State how many of the incident clusters identified in Section 3 have a linked Linear ticket vs. how many have no traceability. Flag any cluster that is recurring or unresolved without a ticket as an escalation candidate.

---

#### 7. Key Takeaways

Write exactly 6 numbered bullet points:

1. The biggest single incident of the month (INC number if declared, cluster name, case count, EPD team, severity, resolution status)
2. The EPD team with the most critical cases and what drove them
3. Any unresolved breakages still open at month end (reference Linear tickets if they exist)
4. Any recurring patterns — same bug appearing in multiple windows, same customer affected twice, same feature area breaking repeatedly, or same incident type recurring from a prior month
5. Month-over-month comparison: total cases, confirmed breakage rate %, critical count, dominant EPD team, and whether this month was healthier or worse — use the specific numbers from Step 3
6. Linear ticket coverage: X of Y incident clusters have a linked ticket. Recommend any clusters that should be escalated.

---

## STEP 5 — PUBLISH TO CONFLUENCE

Using the Atlassian connector, create a new Confluence page with:
- Title: "Cloud Stability Report — [Month] [Year]"
- Space key: SUP
- Parent page ID: 2223046673
- Content: the full report from Step 4, formatted in Confluence storage format with proper headings, bold text, and tables

If a page with this title already exists, update it instead of creating a new one (use `searchConfluenceUsingCql` to find the existing page ID, then `updateConfluencePage`).

After creating or updating the page, save the page URL from the response.

If Confluence page creation fails: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Cloud Stability Report was generated but failed to publish to Confluence. Error: [error message]" Then stop.

---

## STEP 6 — SEND SLACK NOTIFICATION

Using the Slack connector, send a single message to #support-alerts (channel ID C02B4ETL404) tagging Jay Lee and the support-managers group:

"<@U03MH0RAUVD> <!subteam^S046CKNV01E> [Month] [Year] Cloud Stability Report is ready: [Confluence page URL]"

---

## ERROR HANDLING

- If the Databricks query returns 0 rows: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Monthly Cloud Stability Report could not be generated — Databricks query returned no results for [month/year]. Please check the data source."
- If Confluence page creation fails: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Cloud Stability Report was generated but failed to publish to Confluence. Error: [error message]"
- Do not silently fail. Always send Slack notifications reporting success or failure.
