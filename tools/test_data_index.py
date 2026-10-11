"""data_index reads what a spreadsheet saves: a BOM and CRLF in tables.csv and
in a balance.csv (pytest tools/test_data_index.py)."""
import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import data_index  # noqa: E402


def _layout(root, tables: bytes, balance: bytes):
    (root / "alpha").mkdir()
    (root / "tables.csv").write_bytes(tables)
    (root / "alpha" / "balance.csv").write_bytes(balance)
    (root / "alpha" / "things.csv").write_bytes(b"a\n1\n")


def test_reads_a_spreadsheet_saved_index_and_balance(tmp_path):
    _layout(tmp_path, b"\xef\xbb\xbffolder,table\r\nalpha,things\r\n",
            b"\xef\xbb\xbfkey,value,notes\r\nk_one,1,\r\n")
    assert data_index.table_path("things", data=str(tmp_path)) == str(tmp_path / "alpha" / "things.csv")
    assert data_index.balance(data=str(tmp_path)) == {"k_one": 1.0}


def test_a_key_in_two_folders_raises_naming_both(tmp_path):
    _layout(tmp_path, b"folder,table\nalpha,things\nbeta,others\n", b"key,value,notes\nk_one,1,\n")
    (tmp_path / "beta").mkdir()
    (tmp_path / "beta" / "balance.csv").write_bytes(b"key,value,notes\nk_one,2,\n")
    with pytest.raises(ValueError, match="alpha/balance.csv and beta/balance.csv"):
        data_index.balance(data=str(tmp_path))
