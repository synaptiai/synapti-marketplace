def item_count(items):
    return len(items)


def unit_count(items):
    return sum(item["qty"] for item in items)
