-- Google Play's Child Safety Standards require that users can report child
-- safety concerns from inside the app. A dedicated reason lets those reports
-- be found and handled first (docs/child-safety/index.html promises priority
-- review). Placed first so it is also first in the enum's sort order.
alter type public.report_reason add value if not exists 'child_safety' before 'nudity';
