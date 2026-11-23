from datetime import date

from app.services.billing import Due, applicable, build_account

D = lambda i, amt, d, kind="scolarite": Due(i, kind, f"T{i}", amt, d)  # noqa: E731
DUES = [D(1, 100_000, date(2026, 10, 1)), D(2, 80_000, date(2026, 12, 1)), D(3, 80_000, date(2027, 3, 1))]


def test_nothing_paid_before_first_date():
    a = build_account(DUES, 0, date(2026, 9, 20))
    assert a.total_due == 260_000 and a.remaining == 260_000 and a.overdue == 0 and all(ln.late_days == 0 for ln in a.lines)


def test_partial_payment_fills_oldest_first():
    a = build_account(DUES, 130_000, date(2026, 12, 10))
    assert [ln.covered for ln in a.lines] == [100_000, 30_000, 0]
    assert a.remaining == 130_000
    assert a.overdue == 50_000  # line 2 is late (50 000 left), line 3 is not due yet
    assert a.lines[1].late_days == 9


def test_overpayment_becomes_credit_balance_and_nothing_negative():
    a = build_account(DUES, 300_000, date(2027, 6, 1))
    assert a.remaining == 0 and a.overdue == 0 and a.credit_balance == 40_000


def test_credit_note_reopens_the_line():
    paid = build_account(DUES, 100_000, date(2026, 11, 1))
    cancelled = build_account(DUES, 0, date(2026, 11, 1))
    assert paid.overdue == 0 and cancelled.overdue == 100_000


def test_order_follows_dates_not_input_order():
    a = build_account(list(reversed(DUES)), 100_000, date(2027, 4, 1))
    assert a.lines[0].id == 1 and a.lines[0].remaining == 0 and a.overdue == 160_000


def test_negative_credit_never_reduces_the_bill():
    assert build_account(DUES, -5, date(2026, 11, 1)).remaining == 260_000


def test_assigned_scope():
    assert applicable("all", True) and applicable("all", False)
    assert applicable("assigned", True) and not applicable("assigned", False)
    assert applicable("non_assigned", False) and not applicable("non_assigned", True)
