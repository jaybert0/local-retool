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

If the query returns 0 rows: send a Slack DM to U03MH0RAUVD saying "Monthly Cloud Stability Report could not be generated — Databricks query returned no results for [month/year]. Please check the data source." Then stop.

---

## STEP 2 — GENERATE THE REPORT

Analyze the query results and write a Cloud Stability Report for the previous calendar month.
The report preparer is always "Jay Lee, Cloud Stability Engineer."
Use the exact structure below.

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
- The month's dominant incident themes and largest clusters
- Any notable critical incidents or unresolved bugs
- A brief comparison to the prior month if data allows (e.g. "healthier than X" or "higher critical count than X")

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
- Add a blockquote comparing this month's ratio to prior month if data is available

---

#### 2. Breakage by Product Area and EPD Team

Map each case's subject/product area to an EPD team using these rules:
- Hub, permissions, groups, audit logs, SSO, governance → Governance
- Connect, resources, connectors, databases, OAuth, Firebase, Firestore, Retool DB → Resources
- App Building, editor, components, queries, pages, tables, tabs → Apps Foundation or Apps Builder Experience (split based on whether it's infrastructure/query-layer vs UI/component-layer)
- Workflows, automations → Automations
- Assist → Assist

Only count confirmed breakages (Critical + Standard + Unsolved) in these tables.

Table 1 — By product area:
| Product Area | EPD Team | Breakages | Critical | % of Breakages |

Table 2 — By EPD team:
| EPD Team | Total | Critical | Standard | Unsolved |

Add a 2–3 sentence narrative below the tables noting which team led by volume vs. which had the most critical cases.

---

#### 3. Incident Clustering

Group cases that share the same root symptom (same subject pattern + same EPD team + overlapping dates) into clusters.

Table A — Multi-ticket clusters (2 or more cases with the same root cause):
| # | Incident | Cases | Severity | Date(s) | EPD Team | Linear |

For the Linear column: check the linears field. If any case in the cluster has a non-null issue_url, include the ticket ID. Otherwise use "—".

Table B — Single-case incidents:
| # | Incident | Date | Severity | EPD Team |

Table C — Summary by EPD team:
| EPD Team | Incidents | Critical Cases | Notes |

Write a narrative paragraph on the top 1–2 clusters: describe the symptom, affected customers, dates, resolution status, and any linked Linear ticket.

If any cluster remains unresolved, call it out explicitly with the Linear ticket number if one exists.

---

#### 4. Resolution Speed

Table: Outcome | Median Hours to Close | n

Calculate median from the hours_to_close field, grouped by outcome category.
Note: hours_to_close = datediff in minutes / 60 between submitted_at__c and first_solved_at__c.

Below the table, list any breakages still unsolved at month end (outcome__c contains "Unsolved").

---

#### 5. Customer Tier and Plan

Table of confirmed breakages by plan_name_at_create__c:
| Plan | Breakages | % |

Note which plan tier is most affected and whether it's disproportionate relative to expected distribution. Call out any plan tiers that were specifically impacted by a major cluster.

---

#### 6. Engineering Escalations (Linear)

List all unique Linear tickets found in the linears field across all cases. For each:
- Ticket ID and URL
- Title
- Current state (issue_state_name)
- Which cases it's linked to

State how many of the incident clusters identified in Section 3 have a linked Linear ticket vs. how many have no traceability. Flag the next most likely escalation candidate if any cluster is recurring or unresolved without a ticket.

---

#### 7. Key Takeaways

Write exactly 6 numbered bullet points:

1. The biggest single incident of the month (cluster name, case count, EPD team, resolution status)
2. The EPD team with the most critical cases and what drove them
3. Any unresolved breakages still open at month end (reference Linear tickets if they exist)
4. Any recurring patterns — same bug appearing in multiple windows, same customer affected twice, or same feature area breaking repeatedly
5. Month-over-month comparison: breakage rate %, critical count, and whether this month was healthier or worse than the prior month
6. Linear ticket coverage: X of Y incident clusters have a linked ticket. Recommend any clusters that should be escalated.

---

## STEP 3 — PUBLISH TO CONFLUENCE

Using the Atlassian connector, create a new Confluence page with:
- Title: "Cloud Stability Report — [Month] [Year]"
- Space key: SUP
- Parent page ID: 2223046673
- Content: the full report from Step 2, formatted in Confluence storage format with proper headings, bold text, and tables

After creating the page, save the page URL from the response.

If Confluence page creation fails: send a Slack DM to U03MH0RAUVD saying "Cloud Stability Report was generated but failed to publish to Confluence. Error: [error message]" Then stop.

---

## STEP 4 — SEND SLACK NOTIFICATIONS

Using the Slack connector, send a single message to #support-alerts tagging Jay Lee and the support-managers group:

"<@U03MH0RAUVD> <!subteam^S046CKNV01E> [Month] [Year] Cloud Stability Report is ready: [Confluence page URL]"

Send to:
1. Slack channel ID C02B4ETL404 (#support-alerts) — channel post

---

## ERROR HANDLING

- If the Databricks query returns 0 rows: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Monthly Cloud Stability Report could not be generated — Databricks query returned no results for [month/year]. Please check the data source."
- If Confluence page creation fails: send a message to C02B4ETL404 (#support-alerts) tagging <@U03MH0RAUVD> and <!subteam^S046CKNV01E> saying "Cloud Stability Report was generated but failed to publish to Confluence. Error: [error message]"
- Do not silently fail. Always send Slack notifications reporting success or failure.
