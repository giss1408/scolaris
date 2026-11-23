"""Levels of the Ivorian school system and the kinds of fees. Plain constants: a school picks among them, it cannot invent new codes."""

LEVELS = {
    "preschool": ["PS", "MS", "GS"],
    "primary": ["CP1", "CP2", "CE1", "CE2", "CM1", "CM2"],  # exam: CEPE
    "college": ["6e", "5e", "4e", "3e"],  # exam: BEPC
    "lycee": ["2nde", "1ere", "Tle"],  # exam: BAC
}
ALL_LEVELS = [lv for group in LEVELS.values() for lv in group]

FEE_KINDS = ["inscription", "scolarite", "cantine", "transport", "tenue", "fournitures", "assurance", "coges", "examen", "parascolaire"]
PAYMENT_METHODS = ["especes", "wave", "orange_money", "mtn_momo", "moov_money", "virement", "cheque"]
# Mobile Money and bank payments must carry the operator / bank reference: it is what the accountant reconciles against.
METHODS_NEEDING_REFERENCE = {"wave", "orange_money", "mtn_momo", "moov_money", "virement", "cheque"}
DISCOUNT_KINDS = ["fratrie", "personnel", "bourse", "exceptionnelle"]
STAFF_ROLES = ["director", "accountant", "secretary"]
