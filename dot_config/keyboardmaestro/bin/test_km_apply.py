from kmlib import find_duplicate_uids

PUNCH = "9C3A28CA-6CE2-42BD-B325-9D4A6BAFCBF1"
HELLO = "A0000000-0000-4000-8000-CHEZMOI00001"


def test_distinct_uids_report_no_duplicate():
    files = [("punch.kmmacros", {"UID": PUNCH}),
             ("hello-chezmoi.kmmacros", {"UID": HELLO})]
    assert find_duplicate_uids(files) == {}


def test_two_files_that_claim_one_uid_are_reported():
    files = [("punch.kmmacros", {"UID": PUNCH}),
             ("study-session.kmmacros", {"UID": PUNCH})]
    assert find_duplicate_uids(files) == {
        PUNCH: ["punch.kmmacros", "study-session.kmmacros"]
    }


def test_the_report_names_every_file_that_claims_the_uid():
    files = [("c.kmmacros", {"UID": PUNCH}),
             ("a.kmmacros", {"UID": PUNCH}),
             ("b.kmmacros", {"UID": PUNCH})]
    assert find_duplicate_uids(files)[PUNCH] == [
        "a.kmmacros", "b.kmmacros", "c.kmmacros"
    ]


def test_a_clean_file_stays_out_of_the_report():
    files = [("punch.kmmacros", {"UID": PUNCH}),
             ("study-session.kmmacros", {"UID": PUNCH}),
             ("hello-chezmoi.kmmacros", {"UID": HELLO})]
    assert list(find_duplicate_uids(files)) == [PUNCH]


def test_no_macro_file_reports_no_duplicate():
    assert find_duplicate_uids([]) == {}
