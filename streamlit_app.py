#!/usr/bin/env python3
"""
World Cup 2026 Predictions — Streamlit Dashboard + Chat Agent

Run locally:
  streamlit run streamlit_app.py

Deploy to Streamlit Community Cloud:
  1. Push this repo to GitHub
  2. Connect at share.streamlit.io
  3. Add GOOGLE_APPLICATION_CREDENTIALS_JSON secret (paste service account JSON)
"""

import os
import json
import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from google.cloud import bigquery
from google.oauth2 import service_account

# ── Configuration ─────────────────────────────────────────────────────────────

BQ_PROJECT  = "analytics-project-production"
BQ_DATASET  = "ML_WC_2026"
GEMINI_MODEL = "gemini-3.1-flash-lite-preview"
# Get a free Gemini API key at: https://aistudio.google.com/app/apikey
# Then: export GEMINI_API_KEY="your_key" (or add to ~/.zshrc)
def _get_gemini_key():
    if k := os.environ.get("GEMINI_API_KEY", ""):
        return k
    try:
        return st.secrets["GEMINI_API_KEY"]
    except Exception:
        return ""
GEMINI_API_KEY = _get_gemini_key()
LOCAL_KEY   = os.path.expanduser(
    "~/Documents/dbt_assets/analytics-project-production-62efc2ae9c13.json"
)

st.set_page_config(
    page_title="WC 2026 Predictions",
    page_icon="⚽",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ── BigQuery auth ─────────────────────────────────────────────────────────────

@st.cache_resource
def get_bq_client():
    # 1. Streamlit Cloud: secret stored as TOML table [gcp_service_account]
    if "gcp_service_account" in st.secrets:
        creds = service_account.Credentials.from_service_account_info(
            st.secrets["gcp_service_account"]
        )
        return bigquery.Client(project=BQ_PROJECT, credentials=creds)
    # 2. Local dev: use the known keyfile path
    if os.path.exists(LOCAL_KEY):
        return bigquery.Client.from_service_account_json(LOCAL_KEY, project=BQ_PROJECT)
    available = list(st.secrets.keys()) if hasattr(st, "secrets") else []
    st.error(f"No credentials found. Secrets available: {available}")
    st.stop()


def tbl(name):
    return f"`{BQ_PROJECT}.{BQ_DATASET}.{name}`"


@st.cache_data(ttl=300, show_spinner=False)
def run_query(_client, sql):
    return _client.query(sql).to_dataframe()


# ── Data loaders ──────────────────────────────────────────────────────────────

@st.cache_data(ttl=300, show_spinner=False)
def load_fixtures(_client):
    return run_query(_client, f"""
        SELECT
            fixture_id, group_name, group_round, match_number,
            home_team, away_team,
            p_home_win, p_draw, p_away_win,
            ensemble_predicted_result,
            poisson_predicted_result, bqml_predicted_result,
            home_xg, away_xg,
            home_elo, away_elo, elo_edge_label,
            home_form_pts_pct, away_form_pts_pct,
            model_agreement, prediction_confidence,
            max_outcome_prob,
            implied_odds_home, implied_odds_draw, implied_odds_away,
            venue, venue_city, venue_country,
            kickoff_utc, kickoff_local, utc_offset_hours,
            altitude_m, avg_temp_june_c
        FROM {tbl('mart_wc_group_predictions')}
        ORDER BY match_number
    """)


@st.cache_data(ttl=300, show_spinner=False)
def load_bracket(_client):
    return run_query(_client, f"""
        SELECT
            team, group_name, confederation, elo_rating,
            p_finish_1st, p_finish_2nd, p_qualify_r32,
            p_reach_r16, p_reach_qf, p_reach_sf, p_reach_final,
            p_win_tournament, outright_implied_odds, tournament_rank
        FROM {tbl('mart_wc_bracket')}
        ORDER BY p_win_tournament DESC
    """)


@st.cache_data(ttl=300, show_spinner=False)
def load_group_standings(_client):
    return run_query(_client, f"""
        SELECT
            group_name, team,
            avg_pts, avg_goal_diff, avg_goals_scored, avg_goals_conceded,
            p_finish_1st, p_finish_2nd, p_finish_3rd, p_finish_4th,
            p_advance
        FROM {tbl('pred_group_stage_standings')}
        ORDER BY group_name, avg_pts DESC, avg_goal_diff DESC
    """)


@st.cache_data(ttl=300, show_spinner=False)
def load_predictions_vs_actual(_client):
    return run_query(_client, f"""
        SELECT
            group_name, team,
            pred_pts, pred_gd, pred_gf,
            actual_pts, actual_gd, actual_gf,
            actual_position, qualified_direct,
            pts_diff, gd_diff, gf_diff,
            p_finish_1st, p_finish_2nd, p_finish_3rd,
            position_accuracy
        FROM {tbl('mart_predictions_vs_actual')}
        ORDER BY group_name, coalesce(actual_position, 999), team
    """)


@st.cache_data(ttl=300, show_spinner=False)
def load_match_predictions_vs_actual(_client):
    return run_query(_client, f"""
        SELECT
            match_number, group_name, group_round,
            home_team, away_team,
            p_home_win, p_draw, p_away_win, ensemble_predicted_result,
            home_goals, away_goals, actual_result,
            prediction_accurate, actual_outcome_probability,
            home_xg, away_xg, home_xg_diff, away_xg_diff,
            actual_goals_1h, actual_goals_2h,
            actual_home_goals_1h, actual_home_goals_2h,
            actual_away_goals_1h, actual_away_goals_2h
        FROM {tbl('mart_match_predictions_vs_actual')}
        ORDER BY match_number
    """)


@st.cache_data(ttl=300, show_spinner=False)
def load_goalscorers(_client, fixture_id):
    """Load goalscorers for a specific match fixture."""
    return run_query(_client, f"""
        SELECT
            fixture_id, home_team, away_team,
            home_scorers, away_scorers,
            total_goals, home_goals_count, away_goals_count
        FROM {tbl('mart_wc_match_goalscorers')}
        WHERE fixture_id = '{fixture_id}'
        LIMIT 1
    """)


# ── Sidebar ───────────────────────────────────────────────────────────────────

def render_sidebar():
    with st.sidebar:
        st.markdown("## ⚽ WC 2026 Predictions")
        st.caption("BigQuery ML · Poisson · Bookmaker Odds")
        st.divider()
        page = st.radio(
            "Navigate",
            [
                "🗓️  Group Stage",
                "📊  Group Standings",
                "📈  Model Performance",
                "🏆  Tournament Winner",
                "🤖  Match Previews",
                "💬  Chat Agent",
            ],
            label_visibility="collapsed",
        )
        st.divider()
        with st.expander("ℹ️ How to read this page"):
            st.markdown(
                """
**ELO** — Team strength rating built from historical results. A 100-point gap means the stronger side wins ~64% of the time. Updated manually each day.

**xG** — Expected Goals: how many goals each team is likely to score based on their weighted attack/defence strength over the past 5 years.

**Poisson** — Statistical model treating goals as random events. Good at estimating scorelines and goal totals.

**BQML** — BigQuery ML gradient-boosted tree trained on historical match data. Picks up on form, head-to-head, and confederation patterns.

**Ensemble** — Final blended forecast: Poisson 25% + BQML 40% + Bookmaker odds 35%. Confidence badge 🟢🟡🔴 reflects how decisive the leading probability is.
                """
            )
    return page


# ── Page: Group Stage ─────────────────────────────────────────────────────────

def page_group_stage(client):
    st.header("Group Stage Fixtures")

    with st.spinner("Loading fixtures…"):
        fixtures = load_fixtures(client)

    groups = sorted(fixtures["group_name"].unique())
    selected = st.selectbox("Filter by group", ["All Groups"] + list(groups))

    df = fixtures if selected == "All Groups" else fixtures[fixtures["group_name"] == selected]

    conf_icon = {"High": "🟢", "Medium": "🟡", "Low": "🔴"}

    for i, (_, row) in enumerate(df.iterrows()):
        col_info, col_chart, col_meta = st.columns([3, 4, 2])

        with col_info:
            st.markdown(f"**{row['group_name']} · Matchday {row['group_round']}**")
            # Venue: small caption text
            st.caption(f"{row['venue']}, {row['venue_city']}")
            st.markdown(f"### {row['home_team']}  vs  {row['away_team']}")
            # Kickoff: UTC first (white/bright), then local (dimmer caption)
            import pandas as pd
            def fmt_dt(val, fmt="%a %d %b '%y %H:%M"):
                if val is None or (isinstance(val, float) and pd.isna(val)):
                    return ''
                try:
                    return pd.to_datetime(val).strftime(fmt)
                except Exception:
                    return str(val)[:16].replace('T', ' ')
            kickoff_local_str = fmt_dt(row['kickoff_local'])
            kickoff_utc_str   = fmt_dt(row['kickoff_utc'])
            st.markdown(f"<span style='color:white;font-size:0.8rem'>{kickoff_utc_str} (UK Time)</span>", unsafe_allow_html=True)
            st.caption(f"{kickoff_local_str} (Local Time)")
            altitude = int(row['altitude_m']) if row['altitude_m'] is not None else '—'
            temp = int(row['avg_temp_june_c']) if row['avg_temp_june_c'] is not None else '—'
            st.caption(f"{altitude}m altitude  ·  ~{temp}°C avg")
            st.write("")
            st.write("")  # Extra padding to align all charts at Bosnia & Herzegovina level

        with col_chart:
            # Horizontal bar: home at top, draw in middle, away at bottom
            fig = go.Figure(go.Bar(
                y=[row["home_team"], "Draw", row["away_team"]],
                x=[row["p_home_win"], row["p_draw"], row["p_away_win"]],
                orientation="h",
                marker_color=["#2ecc71", "#7f7f7f", "#e74c3c"],
                text=[f"{v:.0%}" for v in [row["p_home_win"], row["p_draw"], row["p_away_win"]]],
                textposition="outside",
            ))
            fig.update_layout(
                height=200,
                margin=dict(l=10, r=60, t=8, b=8),
                xaxis=dict(range=[0, 1.15], showticklabels=False, showgrid=False),
                yaxis=dict(showgrid=False, autorange="reversed"),
                paper_bgcolor="rgba(0,0,0,0)",
                plot_bgcolor="rgba(0,0,0,0)",
                showlegend=False,
            )
            st.plotly_chart(fig, use_container_width=True, key=f"group_stage_{i}", config={"displayModeBar": False})

        with col_meta:
            xg_str = f"{row['home_xg']:.2f} – {row['away_xg']:.2f}"
            st.metric("xG", xg_str)
            st.markdown(f"<span style='color:white;font-size:0.8rem'>ELO &nbsp; {int(row['home_elo'])} – {int(row['away_elo'])}</span>", unsafe_allow_html=True)
            st.caption(row['elo_edge_label'])
            predicted = row["ensemble_predicted_result"].replace("_", " ").title()
            icon = conf_icon.get(row["prediction_confidence"], "⚪")
            st.caption(f"**{predicted}** {icon}")
            if row["model_agreement"] == "Models agree":
                st.caption("✅ Models agree")
            else:
                p = row["poisson_predicted_result"].replace("_", " ").title()
                b = row["bqml_predicted_result"].replace("_", " ").title()
                st.caption(f"⚠️ Poisson: {p} · BQML: {b}")

        st.divider()


# ── Page: Group Standings ─────────────────────────────────────────────────────

def page_standings(client):
    st.header("Group Stage Standings")

    with st.spinner("Loading standings…"):
        standings_df = load_group_standings(client)

    # Display group tables
    st.subheader("Predicted Group Tables")
    st.caption("Based on average outcomes from Monte Carlo simulation across 1,000 scenarios.")

    groups = sorted(standings_df["group_name"].unique())
    
    for group in groups:
        group_data = standings_df[standings_df["group_name"] == group].copy()
        group_data = group_data.reset_index(drop=True)
        
        # Format columns for display
        display_data = group_data[[
            "team", "avg_pts", "avg_goals_scored", "avg_goals_conceded",
            "avg_goal_diff", "p_finish_1st", "p_finish_2nd", "p_finish_3rd", "p_advance"
        ]].copy()
        
        display_data.columns = [
            "Team", "Pts", "GF", "GA", "GD", 
            "1st %", "2nd %", "3rd %", "Qualify %"
        ]
        
        # Format percentages
        for col in ["1st %", "2nd %", "3rd %", "Qualify %"]:
            display_data[col] = (display_data[col] * 100).round(1).astype(str) + "%"
        
        # Format numbers
        display_data["Pts"] = display_data["Pts"].round(1)
        display_data["GF"] = display_data["GF"].round(1)
        display_data["GA"] = display_data["GA"].round(1)
        display_data["GD"] = display_data["GD"].round(1)
        
        # Display table in columns (2 per row)
        col1, col2 = st.columns([1.2, 3])
        with col1:
            st.markdown(f"**Group {group}**")
        with col2:
            st.dataframe(
                display_data,
                use_container_width=True,
                hide_index=True,
                column_config={
                    "Team": st.column_config.TextColumn(width="medium"),
                    "Pts": st.column_config.NumberColumn(width="small"),
                    "GF": st.column_config.NumberColumn(width="small"),
                    "GA": st.column_config.NumberColumn(width="small"),
                    "GD": st.column_config.NumberColumn(width="small"),
                    "1st %": st.column_config.TextColumn(width="small"),
                    "2nd %": st.column_config.TextColumn(width="small"),
                    "3rd %": st.column_config.TextColumn(width="small"),
                    "Qualify %": st.column_config.TextColumn(width="small"),
                }
            )
        st.write("")  # Spacing

    st.divider()
    st.subheader("Qualification Probability Charts")
    st.caption("🟦 Finish 2nd · 🟩 Finish 1st (stacked — total bar = chance of qualifying directly) · 🟧 Qualify as best 3rd-placed team (hidden by default, click legend to show)")

    with st.spinner("Loading bracket…"):
        bracket = load_bracket(client)

    groups = sorted(bracket["group_name"].unique())
    grid = [groups[i : i + 2] for i in range(0, len(groups), 2)]

    for row_groups in grid:
        cols = st.columns(len(row_groups))
        for col, group in zip(cols, row_groups):
            gdf = (
                bracket[bracket["group_name"] == group]
                .sort_values("p_qualify_r32", ascending=True)
            )
            fig = go.Figure()
            fig.add_trace(go.Bar(
                name="Finish 1st",
                x=gdf["p_finish_1st"], y=gdf["team"],
                orientation="h", marker_color="#2ecc71",
            ))
            fig.add_trace(go.Bar(
                name="Finish 2nd",
                x=gdf["p_finish_2nd"], y=gdf["team"],
                orientation="h", marker_color="#3498db",
            ))
            fig.add_trace(go.Bar(
                name="Qualify",
                x=gdf["p_qualify_r32"], y=gdf["team"],
                orientation="h", marker_color="#e67e22",
                visible="legendonly",
            ))
            fig.update_layout(
                title=dict(text=group, font_size=14, x=0, xanchor="left"),
                barmode="overlay",
                height=260,
                margin=dict(l=160, r=20, t=60, b=0),
                xaxis=dict(range=[0, 1], tickformat=".0%", showgrid=False),
                yaxis=dict(showgrid=False),
                legend=dict(orientation="h", y=1.28, yanchor="bottom", font_size=11),
                paper_bgcolor="rgba(0,0,0,0)",
                plot_bgcolor="rgba(0,0,0,0)",
            )
            with col:
                st.plotly_chart(fig, use_container_width=True, key=f"standings_{group}", config={"displayModeBar": False})


# ── Page: Tournament Winner ───────────────────────────────────────────────────

def page_tournament_winner(client):
    st.header("Tournament Winner Probabilities")

    with st.spinner("Loading bracket…"):
        bracket = load_bracket(client)

    tab_chart, tab_full = st.tabs(["📊 Win Probability Chart", "📋 Full Bracket Table"])

    with tab_chart:
        top24 = bracket.head(24).sort_values("p_win_tournament")
        fig = px.bar(
            top24,
            x="p_win_tournament",
            y="team",
            orientation="h",
            color="confederation",
            text=top24["p_win_tournament"].apply(lambda x: f"{x:.1%}"),
            color_discrete_sequence=px.colors.qualitative.Set2,
            labels={"p_win_tournament": "Win Probability", "team": ""},
        )
        fig.update_traces(textposition="outside")
        fig.update_layout(
            height=700,
            xaxis=dict(tickformat=".0%", showgrid=False),
            yaxis=dict(showgrid=False),
            paper_bgcolor="rgba(0,0,0,0)",
            plot_bgcolor="rgba(0,0,0,0)",
            legend_title="Confederation",
        )
        st.plotly_chart(fig, use_container_width=True)

    with tab_full:
        pct_cols = [
            "p_qualify_r32", "p_reach_r16", "p_reach_qf",
            "p_reach_sf", "p_reach_final", "p_win_tournament",
        ]
        display = bracket[[
            "tournament_rank", "team", "group_name", "confederation",
            "elo_rating", *pct_cols, "outright_implied_odds",
        ]].copy()
        display.columns = [
            "Rank", "Team", "Group", "Conf", "ELO",
            "Qual R32", "R16", "QF", "SF", "Final", "Win",
            "Implied Odds",
        ]
        st.dataframe(
            display.style.format({c: "{:.1%}" for c in ["Qual R32", "R16", "QF", "SF", "Final", "Win"]}),
            use_container_width=True,
            hide_index=True,
        )


# ── Page: Model Performance ───────────────────────────────────────────────────

def page_model_performance(client):
    st.header("📈 Model Performance")
    st.caption("Track predicted vs actual outcomes as the tournament progresses.")

    with st.spinner("Loading comparison data…"):
        comp_df = load_predictions_vs_actual(client)
        match_comp_df = load_match_predictions_vs_actual(client)

    # ─── Tab 1: Group Standings Comparison ───
    st.subheader("Predicted vs Actual Group Standings")
    
    groups = sorted(comp_df["group_name"].unique())
    
    for group in groups:
        group_comp = comp_df[comp_df["group_name"] == group].copy()
        
        if group_comp[group_comp["actual_position"].notna()].shape[0] == 0:
            continue  # Skip if no actual results yet
        
        col1, col2 = st.columns(2)
        
        with col1:
            st.markdown(f"**{group} - Predicted**")
            pred_display = group_comp[[
                "team", "pred_pts", "pred_gf", "pred_gd", "p_finish_1st"
            ]].copy()
            pred_display.columns = ["Team", "Pts", "GF", "GD", "1st %"]
            pred_display["1st %"] = (pred_display["1st %"] * 100).round(1).astype(str) + "%"
            for col in ["Pts", "GF", "GD"]:
                pred_display[col] = pred_display[col].round(1)
            st.dataframe(pred_display, use_container_width=True, hide_index=True)
        
        with col2:
            st.markdown(f"**{group} - Actual**")
            actual_display = group_comp[[
                "team", "actual_pts", "actual_gf", "actual_gd", "actual_position"
            ]].copy()
            actual_display.columns = ["Team", "Pts", "GF", "GD", "Pos"]
            for col in ["Pts", "GF", "GD"]:
                actual_display[col] = actual_display[col].round(1)
            actual_display = actual_display.dropna(subset=["Pos"])
            if len(actual_display) > 0:
                st.dataframe(actual_display, use_container_width=True, hide_index=True)
            else:
                st.caption("No match results yet")
        st.write("")

    # ─── Tab 2: Match Accuracy ───
    st.divider()
    st.subheader("Match Prediction Accuracy")
    
    # Filter to completed matches only
    completed = match_comp_df[match_comp_df["prediction_accurate"].notna()].copy()
    
    if len(completed) > 0:
        col1, col2, col3, col4 = st.columns(4)
        
        total_matches = len(completed)
        correct = len(completed[completed["prediction_accurate"] == "correct"])
        accuracy_pct = (correct / total_matches * 100) if total_matches > 0 else 0
        
        with col1:
            st.metric("Matches Played", total_matches)
        with col2:
            st.metric("Predictions Correct", f"{correct}/{total_matches}")
        with col3:
            st.metric("Accuracy", f"{accuracy_pct:.1f}%")
        with col4:
            avg_confidence = completed["actual_outcome_probability"].mean()
            st.metric("Avg Confidence", f"{avg_confidence:.1%}")

        st.divider()
        
        # All matches (scrollable)
        st.markdown(f"**All Completed Matches ({len(completed)} total)**")
        
        # Sort by match number ascending (earliest first)
        all_matches = completed.sort_values("match_number", ascending=True).copy()
        
        # Add predicted goals by half (using 45/55 split: 45% 1H, 55% 2H)
        all_matches["pred_goals_total"] = all_matches["home_xg"] + all_matches["away_xg"]
        all_matches["pred_goals_1h"] = (all_matches["pred_goals_total"] * 0.45).round(1)
        all_matches["pred_goals_2h"] = (all_matches["pred_goals_total"] * 0.55).round(1)
        
        # Format actual total goals
        all_matches["actual_goals_total"] = all_matches["home_goals"] + all_matches["away_goals"]
        
        # Create score strings (handle NaN for future matches)
        all_matches["pred_score"] = all_matches.apply(
            lambda row: f"{row['home_xg']:.0f}-{row['away_xg']:.0f}",
            axis=1
        )
        all_matches["actual_score"] = all_matches.apply(
            lambda row: f"{int(row['home_goals'])}-{int(row['away_goals'])}" 
                        if pd.notna(row['home_goals']) and pd.notna(row['away_goals']) 
                        else "TBD",
            axis=1
        )
        
        # Create display table with all columns
        all_matches_display = all_matches[[
            "match_number", "group_name", "home_team", "away_team",
            "ensemble_predicted_result", "actual_result",
            "pred_score", "actual_score",
            "pred_goals_1h", "actual_goals_1h",
            "pred_goals_2h", "actual_goals_2h",
            "prediction_accurate", "actual_outcome_probability"
        ]].copy()
        
        all_matches_display.columns = [
            "Match", "Group", "Home", "Away",
            "Predicted", "Actual",
            "Pred Score", "Actual Score",
            "Pred 1H Goals", "Actual 1H Goals",
            "Pred 2H Goals", "Actual 2H Goals",
            "Result Correct", "Confidence"
        ]
        
        # Format columns
        all_matches_display["Predicted"] = all_matches_display["Predicted"].str.replace("_", " ").str.title()
        
        # Set Actual to "Pending" if match hasn't been played (Actual Score is "TBD")
        all_matches_display["Actual"] = all_matches_display.apply(
            lambda row: "Pending" if row["Actual Score"] == "TBD" else row["Actual"].replace("_", " ").title(),
            axis=1
        )
        
        all_matches_display["Confidence"] = (all_matches_display["Confidence"] * 100).round(1).astype(str) + "%"
        
        # Round goal columns
        for col in ["Pred 1H Goals", "Pred 2H Goals"]:
            all_matches_display[col] = all_matches_display[col].round(1)
        
        # Display the table
        st.dataframe(all_matches_display, use_container_width=True, hide_index=True, height=600)
        
        # Add color coding legend
        st.markdown("""
        <div style="margin-top: 20px; font-size: 14px;">
        <p><strong>Result Correct Legend:</strong> 
        <span style="background-color: #90EE90; padding: 2px 8px; border-radius: 3px;">● Correct</span>
        <span style="background-color: #FF6B6B; color: white; padding: 2px 8px; border-radius: 3px; margin-left: 10px;">● Incorrect</span>
        <span style="background-color: #FFE5B4; padding: 2px 8px; border-radius: 3px; margin-left: 10px;">● Pending</span>
        </p>
        </div>
        """, unsafe_allow_html=True)
    else:
        st.info("No match results yet. Check back once matches are played!")


# ── Gemini helper (shared by Previews + Chat) ───────────────────────────────

@st.cache_resource
def get_gemini_client():
    """Initialise Gemini API client. Returns None if API key not set."""
    from google import genai
    key = GEMINI_API_KEY
    # Also check Streamlit secrets for deployed version
    try:
        if not key and "GEMINI_API_KEY" in st.secrets:
            key = st.secrets["GEMINI_API_KEY"]
    except Exception:
        pass
    if not key:
        return None
    return genai.Client(api_key=key)


def make_gemini_model(client, system_instruction=None):
    """Wrap google.genai.Client in an interface compatible with the rest of the app."""
    from google.genai import types
    config = (
        types.GenerateContentConfig(system_instruction=system_instruction)
        if system_instruction else None
    )

    class _Model:
        def generate_content(self, prompt):
            return client.models.generate_content(
                model=GEMINI_MODEL, contents=prompt, config=config
            )

        def start_chat(self, history=None):
            return client.chats.create(model=GEMINI_MODEL, config=config)

    return _Model()


# ── Page: Match Previews ──────────────────────────────────────────────────────

def page_match_previews(client):
    st.header("🤖 AI Match Previews")
    st.caption("Gemini generates a preview for any fixture using your prediction data.")

    genai = get_gemini_client()
    if genai is None:
        st.warning(
            "🔑 **Gemini API key not set.** "
            "Get a free key at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey), then restart with:\n\n"
            "```\nexport GEMINI_API_KEY='your_key'\nstreamlit run streamlit_app.py\n```"
        )
        return
    gemini = make_gemini_model(genai, system_instruction=(
        "You are an expert football analyst for the 2026 FIFA World Cup. "
        "Be concise, opinionated, and use football terminology."
    ))

    with st.spinner("Loading fixtures…"):
        fixtures = load_fixtures(client)

    groups = sorted(fixtures["group_name"].unique())
    col_g, col_f = st.columns([1, 3])

    with col_g:
        selected_group = st.selectbox("Group", groups)

    group_fixtures = fixtures[fixtures["group_name"] == selected_group]
    fixture_labels = [
        f"MD{int(r['group_round'])}: {r['home_team']} vs {r['away_team']}"
        for _, r in group_fixtures.iterrows()
    ]

    with col_f:
        selected_label = st.selectbox("Fixture", fixture_labels)

    row = group_fixtures.iloc[fixture_labels.index(selected_label)]

    # Show the stats panel
    st.divider()
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("ELO", f"{int(row['home_elo'])} vs {int(row['away_elo'])}")
    c2.metric("Win prob", f"{row['p_home_win']:.0%} / {row['p_draw']:.0%} / {row['p_away_win']:.0%}")
    c3.metric("xG", f"{row['home_xg']:.2f} – {row['away_xg']:.2f}")
    c4.metric("Confidence", row["prediction_confidence"])
    st.divider()

    # Show goalscorers if match has been played
    with st.spinner("Loading match details…"):
        try:
            goalscorers_df = load_goalscorers(client, row['fixture_id'])
            if goalscorers_df is not None and len(goalscorers_df) > 0:
                gs = goalscorers_df.iloc[0]
                if gs['total_goals'] and gs['total_goals'] > 0:
                    st.subheader("⚽ Goalscorers")
                    gs_cols = st.columns(2)
                    with gs_cols[0]:
                        st.write(f"**{gs['home_team']}** ({gs['home_goals_count']})")
                        if gs['home_scorers']:
                            for scorer in str(gs['home_scorers']).split(', '):
                                st.caption(f"• {scorer}")
                    with gs_cols[1]:
                        st.write(f"**{gs['away_team']}** ({gs['away_goals_count']})")
                        if gs['away_scorers']:
                            for scorer in str(gs['away_scorers']).split(', '):
                                st.caption(f"• {scorer}")
        except Exception as e:
            # Silently fail if goalscorer data not available (not yet played)
            pass

    cache_key = f"preview_{row['fixture_id']}"

    if cache_key in st.session_state:
        st.markdown(st.session_state[cache_key])
    else:
        if st.button("✨ Generate Preview", type="primary"):
            prompt = (
                f"2026 FIFA World Cup — Group {row['group_name']}, Matchday {int(row['group_round'])}\n"
                f"Match: {row['home_team']} vs {row['away_team']}\n\n"
                f"Model data:\n"
                f"- ELO: {row['home_team']} {int(row['home_elo'])} vs {row['away_team']} {int(row['away_elo'])}\n"
                f"- Win probabilities: {row['home_team']} {row['p_home_win']:.1%} | Draw {row['p_draw']:.1%} | {row['away_team']} {row['p_away_win']:.1%}\n"
                f"- Expected goals: {row['home_team']} {row['home_xg']:.2f} — {row['away_team']} {row['away_xg']:.2f}\n"
                f"- Recent form (pts %): {row['home_team']} {row['home_form_pts_pct']:.1%} | {row['away_team']} {row['away_form_pts_pct']:.1%}\n"
                f"- Prediction: {row['ensemble_predicted_result'].replace('_', ' ').title()} ({row['model_agreement']})\n\n"
                f"Write a match preview in exactly this format (max 150 words):\n"
                f"**Form & context:** 2 sentences on recent form and what's at stake.\n"
                f"**Key battle:** One tactical matchup to watch.\n"
                f"**Predicted score:** X–X with one sentence reasoning.\n"
                f"**Upset potential:** Low/Medium/High — one sentence why."
            )
            with st.spinner(f"Generating preview for {row['home_team']} vs {row['away_team']}…"):
                try:
                    response = gemini.generate_content(prompt)
                    narrative = response.text
                    st.session_state[cache_key] = narrative
                    st.markdown(narrative)
                except Exception as e:
                    msg = str(e)
                    if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                        st.warning("⏳ Gemini free-tier quota reached. Try again in a few minutes, or check your usage at [ai.dev/rate-limit](https://ai.dev/rate-limit).")
                    else:
                        st.error(f"Gemini error: {msg}")

    st.divider()
    st.caption("Previews are cached per session. Reload the page to regenerate.")


# ── Page: Chat Agent ──────────────────────────────────────────────────────────

def page_chat(client):
    st.header("💬 Predictions Chat Agent")
    st.caption("Ask anything about the 2026 World Cup — Gemini analyses your predictions data.")

    genai = get_gemini_client()
    if genai is None:
        st.warning(
            "🔑 **Gemini API key not set.** "
            "Get a free key at [aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey), then restart with:\n\n"
            "```\nexport GEMINI_API_KEY='your_key'\nstreamlit run streamlit_app.py\n```"
        )
        return
    # Load prediction context once (cached) — used in system instruction, no extra API call
    @st.cache_data(ttl=300, show_spinner=False)
    def build_context(_client):
        bracket = load_bracket(_client)
        fixtures = load_fixtures(_client)

        top10 = bracket.head(10)[
            ["team", "group_name", "p_win_tournament", "p_reach_final", "p_qualify_r32"]
        ].to_string(index=False)

        upsets = (
            fixtures.nsmallest(8, "max_outcome_prob")[
                ["home_team", "away_team", "group_name", "p_home_win", "p_draw", "p_away_win",
                 "model_agreement", "prediction_confidence"]
            ].to_string(index=False)
        )

        high_conf = (
            fixtures[fixtures["prediction_confidence"] == "High"]
            [["home_team", "away_team", "group_name", "ensemble_predicted_result", "max_outcome_prob"]]
            .head(10)
            .to_string(index=False)
        )

        return (
            f"TOURNAMENT FAVOURITES (top 10 by win probability):\n{top10}\n\n"
            f"MOST UNCERTAIN MATCHES (biggest upset potential):\n{upsets}\n\n"
            f"HIGHEST CONFIDENCE PREDICTIONS:\n{high_conf}\n\n"
            f"Total fixtures: {len(fixtures)} group stage matches across 12 groups (A–L).\n"
            f"Groups with 4 teams each. Top 2 + best 8 third-placed teams advance to Round of 32."
        )

    with st.spinner("Loading prediction context…"):
        context = build_context(client)

    # Context baked into system instruction — no extra API call needed on init
    gemini = make_gemini_model(genai, system_instruction=(
        "You are an expert football analyst assistant for the 2026 FIFA World Cup. "
        "You have access to predictions generated by a BigQuery ML + Poisson ensemble model "
        "trained on 49,000 international matches since 1872, blended with live bookmaker odds. "
        "Answer questions concisely and confidently. Use football terminology. "
        "Be opinionated where the data supports it. Keep responses under 200 words unless asked for detail.\n\n"
        f"CURRENT PREDICTION DATA:\n{context}"
    ))

    # Initialise chat session (no seeding call needed — context is in system instruction)
    if "chat_session" not in st.session_state:
        try:
            st.session_state.chat_session = gemini.start_chat(history=[])
            st.session_state.chat_messages = []
        except Exception as e:
            msg = str(e)
            if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                st.warning("⏳ Gemini quota reached. Try again in a few minutes — [check usage](https://ai.dev/rate-limit).")
            else:
                st.error(f"Could not start Gemini session: {msg}")
            return

    # Render existing messages
    for msg in st.session_state.chat_messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    # Suggestions for first-time users
    if not st.session_state.chat_messages:
        st.markdown("**Try asking:**")
        suggestions = [
            "Who are the top 3 favourites to win?",
            "Which match has the biggest upset potential?",
            "How do the hosts (USA, Mexico, Canada) look?",
            "Which group is most competitive?",
            "What are Argentina's chances of repeating?",
        ]
        cols = st.columns(len(suggestions))
        for col, suggestion in zip(cols, suggestions):
            if col.button(suggestion, use_container_width=True):
                st.session_state._prefill = suggestion
                st.rerun()

    # Handle prefill from suggestion buttons
    prompt = st.session_state.pop("_prefill", None)
    if not prompt:
        prompt = st.chat_input("Ask about a team, match, group, or upset…")

    if prompt:
        st.session_state.chat_messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.markdown(prompt)

        with st.chat_message("assistant"):
            with st.spinner("Thinking…"):
                try:
                    response = st.session_state.chat_session.send_message(prompt)
                    answer = response.text
                    st.markdown(answer)
                    st.session_state.chat_messages.append({"role": "assistant", "content": answer})
                except Exception as e:
                    msg = str(e)
                    if "429" in msg or "RESOURCE_EXHAUSTED" in msg:
                        answer = "⏳ Gemini free-tier quota reached. Try again in a few minutes, or check your usage at https://ai.dev/rate-limit."
                    else:
                        answer = f"Sorry, something went wrong: {msg}"
                    st.warning(answer)
                    st.session_state.chat_messages.append({"role": "assistant", "content": answer})
        st.rerun()


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    page = render_sidebar()

    try:
        client = get_bq_client()
    except Exception as e:
        st.error(f"Could not connect to BigQuery: {e}")
        st.info("Set `GOOGLE_APPLICATION_CREDENTIALS` or ensure the keyfile exists at the path in the script.")
        return

    page_map = {
        "🗓️  Group Stage":      page_group_stage,
        "📊  Group Standings":   page_standings,
        "📈  Model Performance": page_model_performance,
        "🏆  Tournament Winner": page_tournament_winner,
        "🤖  Match Previews":    page_match_previews,
        "💬  Chat Agent":        page_chat,
    }
    page_map[page](client)


if __name__ == "__main__":
    main()
