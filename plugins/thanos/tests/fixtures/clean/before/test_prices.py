from prices import item_count


def test_item_count():
    assert item_count([{"qty": 2}, {"qty": 1}]) == 2
