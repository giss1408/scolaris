import struct
import zlib

from tests.conftest import make_school, make_staff
from tests.test_academics import class_with_students
from tests.test_api import student
from tests.test_parent import parent_headers


def png(w=64, h=64, extra=b"") -> bytes:
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    chunk = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))  # noqa: E731
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"\x00\x00\x00\x00")) + chunk(b"IEND", b"") + extra


def jpeg(w=64, h=64) -> bytes:
    return b"\xff\xd8" + b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00" + b"\xff\xc0" + struct.pack(">HBHHBBBB", 11, 8, h, w, 1, 1, 0x11, 0) + b"\xff\xd9"


def put(client, h, data, ctype="image/png"):
    return client.put("/v1/school/logo", content=data, headers={**h, "Content-Type": ctype})


async def test_the_director_sets_the_logo_and_everyone_at_the_school_gets_it(client, school):
    data = png()
    r = await put(client, school["director"], data)
    assert r.status_code == 200 and r.json()["has_logo"] is True and len(r.json()["logo_version"]) == 16
    for who in ("director", "secretary", "accountant", "teacher"):
        got = await client.get("/v1/school/logo", headers=school[who])
        assert got.status_code == 200 and got.content == data and got.headers["content-type"] == "image/png", who
        assert got.headers["x-content-type-options"] == "nosniff" and "private" in got.headers["cache-control"]
    me = (await client.get("/v1/me", headers=school["director"])).json()["school"]
    assert me["has_logo"] is True and me["logo_version"] == r.json()["logo_version"]
    # the app asks again with the validator: nothing is sent while the logo is unchanged
    etag = (await client.get("/v1/school/logo", headers=school["director"])).headers["etag"]
    assert (await client.get("/v1/school/logo", headers={**school["director"], "If-None-Match": etag})).status_code == 304
    # a new logo changes the version, and a JPEG is fine
    r2 = await put(client, school["director"], jpeg(), "image/jpeg")
    assert r2.status_code == 200 and r2.json()["logo_version"] != r.json()["logo_version"]
    assert (await client.get("/v1/school/logo", headers=school["director"])).headers["content-type"] == "image/jpeg"


async def test_only_what_is_really_a_small_png_or_jpeg_is_accepted(client, school):
    d = school["director"]
    cases = {
        "svg": (b'<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>', "image/svg+xml", "image_format"),
        "text renamed as png": (b"not an image at all, only text", "image/png", "image_format"),
        "html declared as jpeg": (b"<html><body>hi</body></html>", "image/jpeg", "image_format"),
        "gif": (b"GIF89a" + b"\x00" * 40, "image/gif", "image_format"),
        "too big (file)": (png(extra=b"\x00" * (512 * 1024)), "image/png", "image_too_large"),
        "too small (pixels)": (png(8, 8), "image/png", "image_size"),
        "too large (pixels)": (png(5000, 5000), "image/png", "image_size"),
        "empty": (b"", "image/png", "empty_image"),
    }
    for name, (data, ctype, detail) in cases.items():
        r = await put(client, d, data, ctype)
        assert r.status_code == 400 and r.json()["detail"] == detail, name
    assert (await client.get("/v1/school/logo", headers=d)).status_code == 404  # nothing was stored
    # a PNG sent with a wrong declared type is still a PNG (we trust the content, not the header)
    assert (await put(client, d, png(), "text/plain")).status_code == 200


async def test_who_may_set_or_remove_it(client, school):
    for who in ("secretary", "accountant", "teacher"):
        assert (await put(client, school[who], png())).status_code == 403, who
    await put(client, school["director"], png())
    assert (await client.delete("/v1/school/logo", headers=school["secretary"])).status_code == 403
    assert (await client.delete("/v1/school/logo", headers=school["director"])).json() == {"has_logo": False}
    assert (await client.get("/v1/school/logo", headers=school["director"])).status_code == 404
    assert (await client.get("/v1/me", headers=school["director"])).json()["school"]["has_logo"] is False


async def test_each_school_has_its_own_logo(client, school):
    mine = png(64, 64)
    await put(client, school["director"], mine)
    sid2, _ = await make_school("Ecole B")
    other, _ = await make_staff(sid2, "director", "Directrice B")
    assert (await client.get("/v1/school/logo", headers=other)).status_code == 404  # B has none: it never sees A's
    theirs = jpeg(96, 96)
    await put(client, other, theirs, "image/jpeg")
    assert (await client.get("/v1/school/logo", headers=other)).content == theirs
    assert (await client.get("/v1/school/logo", headers=school["director"])).content == mine


async def test_a_parent_gets_the_logo_of_the_schools_of_her_children_only(client, school):
    room, e, sub = await class_with_students(client, school, names=("Aya",))
    await client.post("/v1/students", json=student(room, last_name="Traore", first_names="Fanta"), headers=school["secretary"])
    data = png()
    await put(client, school["director"], data)
    me = parent_headers("+2250701020304")
    kids = (await client.get("/v1/parent/children", headers=me)).json()
    assert kids[0]["has_logo"] is True and kids[0]["school_id"] == school["id"] and kids[0]["logo_version"]
    got = await client.get(f"/v1/parent/schools/{school['id']}/logo", headers=me)
    assert got.status_code == 200 and got.content == data
    assert (await client.get(f"/v1/parent/schools/{school['id']}/logo", headers=parent_headers("+2250909090909"))).status_code == 404  # not her school
    sid2, _ = await make_school("Ecole B")
    assert (await client.get(f"/v1/parent/schools/{sid2}/logo", headers=me)).status_code == 404
    assert (await client.get(f"/v1/parent/schools/{school['id']}/logo", headers=school["director"])).status_code == 403  # a staff token is not a parent
