from decimal import Decimal as D

from app.services.grades import annual_average, honour, passes, period_average, rank_all, subject_average


def test_subject_average_normalises_and_ignores_absences():
    assert subject_average([(D("14"), 20, False), (D("8"), 10, False)]) == D("15.00")  # 14/20 and 8/10 = 16/20
    assert subject_average([(D("12"), 20, False), (None, 20, True)]) == D("12.00")  # absent is not a zero
    assert subject_average([(None, 20, True)]) is None
    assert subject_average([]) is None


def test_period_average_uses_coefficients_and_skips_empty_or_zero_coef_subjects():
    avgs = {1: D("10"), 2: D("16"), 3: None, 4: D("2")}
    assert period_average(avgs, {1: 2, 2: 1, 3: 3, 4: 0}) == D("12.00")  # (10*2+16)/3 ; no grade yet and coef 0 do not count
    assert period_average({1: None}, {1: 2}) is None
    assert period_average({1: D("9.99")}, {1: 3}) == D("9.99")


def test_rounding_is_half_up_to_two_decimals():
    assert period_average({1: D("10.00"), 2: D("10.01")}, {1: 1, 2: 1}) == D("10.01")  # 10.005 -> 10.01
    assert subject_average([(D("10.00"), 20, False), (D("10.01"), 20, False)]) == D("10.01")


def test_ranks_share_position_on_ties_and_skip_next():
    r = rank_all({1: D("15"), 2: D("12"), 3: D("12"), 4: D("9"), 5: None})
    assert (r[1].position, r[1].tie) == (1, False)
    assert (r[2].position, r[2].tie) == (2, True) and (r[3].position, r[3].tie) == (2, True)
    assert (r[4].position, r[4].tie) == (4, False)  # 3rd is skipped
    assert 5 not in r and r[1].of == 4


def test_honours_and_overrides():
    assert honour(D("16")) == "felicitations" and honour(D("15.99")) == "encouragements"
    assert honour(D("14")) == "encouragements" and honour(D("12")) == "tableau_honneur" and honour(D("11.99")) is None
    assert honour(D("15"), {"felicitations": 15}) == "felicitations"
    assert honour(None) is None


def test_annual_average_and_pass():
    assert annual_average([D("10"), None, D("13")]) == D("11.50")
    assert annual_average([None]) is None
    assert passes(D("10")) is True and passes(D("9.99")) is False and passes(None) is None
