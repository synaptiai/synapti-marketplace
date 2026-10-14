from prices import item_count, unit_count


def test_item_count():
    assert item_count([{"qty": 2}, {"qty": 1}]) == 2


def test_unit_count():
    assert unit_count([{"qty": 2}, {"qty": 1}]) == 3
    assert unit_count([]) == 0
