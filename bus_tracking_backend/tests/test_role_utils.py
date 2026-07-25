from utils.auth_utils import normalize_role


def test_normalize_role_handles_string_and_enum_values():
    assert normalize_role('ADMIN') == 'admin'
    assert normalize_role('driver') == 'driver'
    assert normalize_role('staff') == 'staff'
    assert normalize_role('student') == 'student'
    assert normalize_role(None) == 'student'
