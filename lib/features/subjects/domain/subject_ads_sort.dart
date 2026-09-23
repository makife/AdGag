/// Subject page tabs (CLAUDE.md section 10). `trending` is a lightweight
/// recency-weighted interim heuristic (SOLD count within the last 7 days)
/// — the real heuristic ranking described in section 16 is Phase F work;
/// this is deliberately simple, not a placeholder alias for `top`.
enum SubjectAdsSort { trending, top, newest }
