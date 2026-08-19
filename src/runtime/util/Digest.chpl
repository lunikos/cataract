module Digest {
  private use CTypes;

  param SHA1_BYTES = 20;

  private inline proc rotl(v: uint(32), bits: int): uint(32) {
    return (v << bits) | (v >> (32 - bits));
  }

  proc sha1(const ref message: [] uint(8), length: int, ref digest: [] uint(8)) {
    var h0: uint(32) = 0x67452301;
    var h1: uint(32) = 0xEFCDAB89;
    var h2: uint(32) = 0x98BADCFE;
    var h3: uint(32) = 0x10325476;
    var h4: uint(32) = 0xC3D2E1F0;

    const padded = ((length + 8) / 64 + 1) * 64;
    var block: [0..<64] uint(8);
    var w: [0..<80] uint(32);

    var at = 0;
    while at < padded {
      for i in 0..<64 {
        const pos = at + i;
        if pos < length then block[i] = message[pos];
        else if pos == length then block[i] = 0x80;
        else if pos >= padded - 8 {
          const shift = (padded - 1 - pos) * 8;
          block[i] = (((length: uint(64)) * 8) >> shift): uint(8);
        } else {
          block[i] = 0;
        }
      }

      for i in 0..<16 do
        w[i] = (block[i * 4]: uint(32) << 24) | (block[i * 4 + 1]: uint(32) << 16) |
               (block[i * 4 + 2]: uint(32) << 8) | block[i * 4 + 3]: uint(32);
      for i in 16..<80 do
        w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);

      var a = h0, b = h1, c = h2, d = h3, e = h4;
      for i in 0..<80 {
        var f: uint(32);
        var k: uint(32);
        if i < 20 {
          f = (b & c) | ((~b) & d);
          k = 0x5A827999;
        } else if i < 40 {
          f = b ^ c ^ d;
          k = 0x6ED9EBA1;
        } else if i < 60 {
          f = (b & c) | (b & d) | (c & d);
          k = 0x8F1BBCDC;
        } else {
          f = b ^ c ^ d;
          k = 0xCA62C1D6;
        }
        const tmp = rotl(a, 5) + f + e + k + w[i];
        e = d;
        d = c;
        c = rotl(b, 30);
        b = a;
        a = tmp;
      }

      h0 += a;
      h1 += b;
      h2 += c;
      h3 += d;
      h4 += e;
      at += 64;
    }

    const words = [h0, h1, h2, h3, h4];
    for i in 0..<5 {
      digest[i * 4]     = (words[i] >> 24): uint(8);
      digest[i * 4 + 1] = (words[i] >> 16): uint(8);
      digest[i * 4 + 2] = (words[i] >> 8): uint(8);
      digest[i * 4 + 3] = words[i]: uint(8);
    }
  }

  private const BASE64_ALPHABET =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  proc base64Encode(const ref data: [] uint(8), length: int): string {
    var sb = "";
    var i = 0;
    while i + 2 < length {
      const triple = (data[i]: int << 16) | (data[i + 1]: int << 8) | data[i + 2]: int;
      sb += BASE64_ALPHABET[(triple >> 18) & 0x3f];
      sb += BASE64_ALPHABET[(triple >> 12) & 0x3f];
      sb += BASE64_ALPHABET[(triple >> 6) & 0x3f];
      sb += BASE64_ALPHABET[triple & 0x3f];
      i += 3;
    }

    const left = length - i;
    if left == 1 {
      const triple = data[i]: int << 16;
      sb += BASE64_ALPHABET[(triple >> 18) & 0x3f];
      sb += BASE64_ALPHABET[(triple >> 12) & 0x3f];
      sb += "==";
    } else if left == 2 {
      const triple = (data[i]: int << 16) | (data[i + 1]: int << 8);
      sb += BASE64_ALPHABET[(triple >> 18) & 0x3f];
      sb += BASE64_ALPHABET[(triple >> 12) & 0x3f];
      sb += BASE64_ALPHABET[(triple >> 6) & 0x3f];
      sb += "=";
    }
    return sb;
  }

  proc sha1Base64(input: string): string {
    const n = input.numBytes;
    var raw: [0..<max(1, n)] uint(8);
    for i in 0..<n do raw[i] = input.byte(i);
    var sum: [0..<SHA1_BYTES] uint(8);
    sha1(raw, n, sum);
    return base64Encode(sum, SHA1_BYTES);
  }

  proc hexDigest(const ref data: [] uint(8), length: int): string {
    const digits = "0123456789abcdef";
    var sb = "";
    for i in 0..<length {
      sb += digits[(data[i] >> 4): int];
      sb += digits[(data[i] & 0xf): int];
    }
    return sb;
  }
}
