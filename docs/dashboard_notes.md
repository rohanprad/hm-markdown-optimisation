# Dashboard notes

Design and data model behind the Power BI dashboard ([powerbi/HM Markdown.pbip](../powerbi/)).
Audience: a merchandising team reviewing markdowns weekly. Three pages: **Overview** (the answer),
**What worked** (the evidence), **Markdown list** (the action).

## Data model

| Table | Source | Rows | Role |
|---|---|---|---|
| `markdown_candidates` | BigQuery `hm.markdown_candidates` | 7,541 | Live full-price lines; the candidate flag, rate of sale and suggested depth |
| `markdown_effect` | BigQuery `hm.markdown_effect` | 19,668 | One row per past markdown, with its adjusted lift |
| `weekly_summary` | BigQuery `hm.weekly_summary` | 1,460 | Units by week, department and price status |
| `Department` | Power Query (distinct departments from `weekly_summary`) | 5 | Shared dimension |

- **Import mode, summarised tables only.** The 31.8M-row transactions table stays in BigQuery; Power BI
  reads the finished outputs of the SQL steps. Import also keeps the report working independently of the
  warehouse.
- **One shared `Department` dimension**, related one-to-many to each fact table, so a single slicer
  filters every page (a small star schema).
- **Built in Power Query, not as a DAX calculated table.** A calculated table's columns only exist after
  DAX runs, and Power BI validates relationships to it before that when opening a project file. A Power
  Query table has its columns from the start.

## Measures

Each measure lives on the table it calculates from, in a **Measures** display folder.

| Measure | DAX | Purpose |
|---|---|---|
| Candidates | `CALCULATE(COUNTROWS(markdown_candidates), markdown_candidates[is_candidate] = TRUE())` | Lines to mark down |
| Live Full-Price Lines | `COUNTROWS(markdown_candidates)` | Denominator for share of range |
| Candidates % of Range | `DIVIDE([Candidates], [Live Full-Price Lines])` | How much of the range is slow |
| Candidates % of Revenue | `DIVIDE(CALCULATE(SUM(…[revenue_now_wk]), …[is_candidate] = TRUE()), SUM(…[revenue_now_wk]))` | How little revenue those lines bring in |
| Expected Extra Units (4 wks) | `SUMX(FILTER(markdown_candidates, [is_candidate]), [ros_now] * 4 * ([expected_unit_lift] - 1))` | Units the markdown should add, using each department's past lift |
| Recommended Depth | `SELECTEDVALUE(markdown_candidates[recommended_depth], "Varies")` | Tooltip on the department chart |
| Markdowns Analysed | `COUNTROWS(markdown_effect)` | Evidence base |
| Median Unit Lift | `MEDIAN(markdown_effect[adjusted_unit_lift])` | Typical sales lift vs similar full-price products |
| Median Revenue Change % | `MEDIAN(markdown_effect[adjusted_revenue_change]) - 1` | Typical revenue change |
| % Markdowns Grew Revenue | `DIVIDE(COUNTROWS(FILTER(markdown_effect, [adjusted_revenue_change] >= 1)), [Markdowns Analysed])` | How reliable a depth band is |
| % Units Marked Down | `DIVIDE(CALCULATE(SUM(weekly_summary[units]), [price_status] = "Marked down"), CALCULATE(SUM(weekly_summary[units]), [price_status] <> "Launched before data"))` | Sale seasons over time |

**Median, not average:** a few products jumped from 2 to 60 units a week after a markdown. An average is
pulled up by those; the median shows the typical result.

## Pages

**Overview.** Four KPI cards (lines to mark down, share of range, share of revenue, extra units expected);
a recommendation panel stating what to do, the depth, what to avoid and the timing; candidates by
department (sorted largest first, suggested depth in the tooltip); and the weekly share of units sold at
markdown, which shows the sale seasons.

**What worked.** Three KPI cards; revenue change and unit lift by markdown depth, with the 30–50% band
highlighted; a department × depth matrix with a red–white–green colour scale centred on zero, so losses
stand out; and a short panel stating the takeaways.

**Markdown list.** Department, product type and suggested-depth slicers, a count of lines, and a table of
candidates sorted slowest first. Rate of sale is shown as units in the last four weeks rather than a
fractional weekly rate, and a dash marks lines with no sales in the prior four weeks.

## Design choices

- **One accent colour for the answer.** Red marks the recommendation and the winning depth band; everything
  else is black, grey or white.
- **Statements, not labels:** headings and panels say what the data means, not just what it shows.
- **Navigation** in a fixed sidebar, with source and data notes there, so every page carries its context.
- **Alt text** on every chart, card and table.
- **Prices are anonymised** in the source data, so every result is shown as a percentage or a count, never £.

## Opening the report

Open `powerbi/HM Markdown.pbip` in Power BI Desktop (Power BI Project format). To refresh it against your own
data, run the SQL in `sql/` in your own BigQuery project, then point the three table sources at that project
in Power Query.
