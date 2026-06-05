# Dashboard Parity Checklist (React web → Flutter)

Tracks every web dashboard element and its Flutter status. Heavy widgets are
intentionally deferred to the phase that owns their data/logic — they appear on
the Flutter dashboard now as tappable placeholder cards so the layout matches.

| # | Web widget | Flutter status | Notes / target phase |
|---|------------|----------------|----------------------|
| 1 | Greeting + role badge | ✅ Done | — |
| 2 | StatCard ×4 (Employees/Profile, Hours, Tasks, Leave) | ✅ Done | Real RLS-scoped data, tap-through |
| 3 | AnnouncementsWidget | ✅ Done | Active + pinned-first |
| 4 | Leave balances (part of PersonalReports) | ✅ Done | Standalone card |
| 5 | TasksWidget (recent list) | ✅ Done | Read-only, taps to Tasks |
| 6 | LeaveWidget (recent requests) | ✅ Done | Own (employee) / team (manager) |
| 7 | DailyTimelineWidget | ✅ Done | Milestones + deadlines + holidays |
| 8 | PersonalReportsWidget (employee) | ✅ Done | Attendance progress, manager(s), teammates, annual leave |
| 9 | TeamReportsWidget (manager) | ✅ Done* | Team size, clocked-in, pending leave, task % — *"top performers" deferred |
| 10 | ClockWidget (clock in/out/break/pause) | ✅ Done (Phase 4) | Live TimeClockCard on dashboard + Attendance |
| 11 | RealTimeAttendanceWidget (managers) | ✅ Done (Phase 4) | RealtimeAttendanceCard: today working/break/paused/out |
| 12 | PerformanceChart | ⏳ Placeholder | **Phase 7** — hours-vs-target chart |
| 13 | CompanyCalendar (full calendar + add events) | ⏳ Placeholder | **Later phase** — own screen |
| 14 | GlobalTimeZoneWidget | ❎ Skipped | Disabled/commented out in the web app too |

## Still pending (build in their proper phase)
- [ ] ClockWidget — Phase 4
- [ ] RealTimeAttendanceWidget — Phase 4
- [ ] PerformanceChart — Phase 4/7
- [ ] CompanyCalendar — later phase
- [ ] TeamReports "top performers" list — when Attendance/Tasks data is richer

## Notes
- All implemented widgets are **read-only** and rely on Supabase RLS for scope.
- No Supabase schema changes were made.
- "Hours this month" and attendance progress use the business formula
  `(clock_out - clock_in) - break - pause`.
