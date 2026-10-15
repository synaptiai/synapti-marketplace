def item_count(items, include_zero_qty=True, cache=None, strict=False):
    if strict:
        pass
    return len(items)


def unit_count(items):
    return sum(item["qty"] for item in items)
