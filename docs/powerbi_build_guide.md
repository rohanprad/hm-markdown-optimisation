# Power BI Build Guide

Three pages, for a merchandising team: **Overview → What worked → Markdown list**.
Build time: about 2–3 hours.

---

## 1. Connect to BigQuery

1. Power BI Desktop → **Get data** → search **Google BigQuery** → **Connect**.
2. **Sign in** with the Google account that owns `data-portfolio-509915`.
3. Expand `data-portfolio-509915` → `hm`, and tick these three tables only:

| Table | Rows | Used on |
|---|---|---|
| `markdown_candidates` | 7,541 | Overview, Markdown list |
| `markdown_effect` | 19,668 | What worked |
| `weekly_summary` | ~1,500 | Overview trend |

4. Click **Load** and choose **Import** (not DirectQuery). The tables are small,
   and Import keeps your dashboard working after the BigQuery sandbox deletes the
   tables (60 days after creation).

**Why not load `transactions`?** 31.8M rows is the raw data. Power BI should read
the finished, summarised tables. The heavy lifting stays in SQL.

## 2. Power Query tidy-up

In **Transform data**:
- `markdown_candidates`: rename `is_candidate` values: right-click → Replace
  values `true` → `Candidate`, `false` → `OK`. (Or keep True/False and use a
  slicer label.)
- Check data types: `week_start`, `launch_week`, `markdown_week` = **Date**;
  lifts and ratios = **Decimal number**.

## 3. Model: one Department table

Three tables each have `index_group_name`. Create one shared Department table so a
single slicer filters every page.

**Modelling → New table:**

```DAX
Department =
DISTINCT (
    UNION (
        DISTINCT ( markdown_candidates[index_group_name] ),
        DISTINCT ( markdown_effect[index_group_name] ),
        DISTINCT ( weekly_summary[index_group_name] )
    )
)
```

*In the finished project this table is built in **Power Query** instead
(`weekly_summary` → keep `index_group_name` → Remove duplicates). A Power Query
table's columns exist before any DAX runs, so Power BI can check relationships to
it as soon as the file opens. Both approaches give the same result.*

*Why `DISTINCT` and not `VALUES`?* `VALUES` includes a hidden "blank" row that
depends on relationships. Once you relate the fact tables back to this table,
that creates a circular dependency error.

In **Model view**, drag `Department[index_group_name]` onto `index_group_name`
in each of the three tables (one-to-many, single direction).

This shared dimension lets one slicer filter every fact table: a small star schema.

## 4. DAX measures

In the finished project (`powerbi/HM Markdown.pbip`), each measure lives on the
table it calculates from, in a **Measures** display folder.

```DAX
-- What worked (markdown_effect)
Markdowns Analysed = COUNTROWS ( markdown_effect )

Median Unit Lift = MEDIAN ( markdown_effect[adjusted_unit_lift] )

Median Revenue Change % = MEDIAN ( markdown_effect[adjusted_revenue_change] ) - 1

% Markdowns Grew Revenue =
DIVIDE (
    COUNTROWS ( FILTER ( markdown_effect, markdown_effect[adjusted_revenue_change] >= 1 ) ),
    [Markdowns Analysed]
)

-- Candidates (markdown_candidates)
Live Full-Price Lines = COUNTROWS ( markdown_candidates )

Candidates =
CALCULATE ( COUNTROWS ( markdown_candidates ), markdown_candidates[is_candidate] = TRUE () )

Candidates % of Range = DIVIDE ( [Candidates], [Live Full-Price Lines] )

Candidates % of Revenue =
DIVIDE (
    CALCULATE ( SUM ( markdown_candidates[revenue_now_wk] ), markdown_candidates[is_candidate] = TRUE () ),
    SUM ( markdown_candidates[revenue_now_wk] )
)

Expected Extra Units (4 wks) =
SUMX (
    FILTER ( markdown_candidates, markdown_candidates[is_candidate] = TRUE () ),
    markdown_candidates[ros_now] * 4 * ( markdown_candidates[expected_unit_lift] - 1 )
)

-- Trend (weekly_summary)
% Units Marked Down =
DIVIDE (
    CALCULATE ( SUM ( weekly_summary[units] ), weekly_summary[price_status] = "Marked down" ),
    CALCULATE ( SUM ( weekly_summary[units] ), weekly_summary[price_status] <> "Launched before data" )
)
```

**Formatting:** `%` measures → Percentage, 0 decimals. Lifts → Decimal, 1 decimal,
then add an "×" suffix via custom format `0.0"×"`.

**Why MEDIAN not AVERAGE?** A few products went from 2 to 60 units a week. Averages
get dragged up by these; the median shows the typical result.

**Expected results (to check your build):** with no filters,
Candidates = 2,122 · Candidates % of Range = 28% · Candidates % of Revenue = 3% ·
Expected Extra Units ≈ 13,000 · Median Revenue Change % for 30–50% = 45%.

## 5. Pages

### Page 1: Overview (the answer)

| Position | Visual | Fields |
|---|---|---|
| Top | **Text box** (the recommendation) | "Mark down 2,122 slow full-price lines now at 30–50% (Menswear 50%+). Avoid shallow 15–30% cuts." |
| Row of cards | **4 × Card** | `Candidates`, `Candidates % of Range`, `Candidates % of Revenue`, `Expected Extra Units (4 wks)` |
| Left | **Clustered bar** | Y: `Department[index_group_name]`, X: `Candidates`, Tooltip: `markdown_candidates[recommended_depth]` |
| Right | **Line chart** | X: `weekly_summary[week_start]`, Y: `% Units Marked Down`. Title: "Sale seasons: share of units sold at markdown" |
| Top right | **Slicer** | `Department[index_group_name]` (dropdown) |

### Page 2: What worked (the evidence)

| Position | Visual | Fields |
|---|---|---|
| Left | **Clustered column** | X: `markdown_effect[depth_band]`, Y: `Median Revenue Change %`. Title: "Revenue change vs similar full-price products" |
| Middle | **Clustered column** | X: `depth_band`, Y: `Median Unit Lift` |
| Right | **Card** | `% Markdowns Grew Revenue` (reacts to clicks on the charts) |
| Bottom | **Matrix** | Rows: `Department[index_group_name]`, Columns: `depth_band`, Values: `Median Revenue Change %`. **Conditional formatting → Background colour** (red → green) |
| Text box | Insight | "30–50% grew revenue most in 4 of 5 departments. Menswear responds to deeper cuts; Sport lost revenue at 50%+." |

Filter the page: `markdown_effect[depth_band]` is not blank.

### Page 3: Markdown list (the action)

| Position | Visual | Fields |
|---|---|---|
| Top | **Slicers** | Department, `product_type_name`, `recommended_depth` |
| Main | **Table** | `prod_name`, `product_type_name`, `index_group_name`, `colour_group_name`, `weeks_on_sale`, `units_last_4wk`, `ros_vs_peers`, `trend_label`, `recommended_depth` |

- Visual-level filter: `is_candidate` = True.
- Sort by `ros_vs_peers` ascending (slowest first).
- Format `ros_vs_peers` as %. Add **data bars** to it.
- Rename columns for the audience: "Units sold (4 wks)", "Speed vs similar lines",
  "vs prior 4 wks" (a dash means no sales in the prior 4 weeks), "Suggested markdown".

## 6. Finish

- Add a footer text box on each page: *"Source: H&M transactions via Kaggle, Sep 2018–Sep
  2020. Prices anonymised; results shown as % changes."*
- Keep colours simple: one accent colour for "action" items, grey for the rest.
- Export screenshots of each page into `dashboard/` for the README.
- Optionally upload the `.pbix` to [NovyPro](https://www.novypro.com) for a live link.
