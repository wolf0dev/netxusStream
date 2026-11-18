/// DES / 3DES (DESede/ECB/PKCS5Padding) en Dart puro, sin dependencias.
///
/// Compatible con `javax.crypto.Cipher("DESede/ECB/PKCS5Padding")`, que es lo
/// que usa el portal de WiwyXuper. Incluye la "envoltura" exacta del APK:
///
///     cuerpo = hex( ascii( base64( 3DES(json) ) ) )
///
/// Las tablas de expansión y las S-box ya permutadas se calculan una sola vez,
/// de modo que descifrar los ~3 MB de `getLiveData` sigue siendo rápido en un
/// televisor.
library;

import 'dart:convert';
import 'dart:typed_data';

// ------------------------------------------------------------------ tablas DES

const List<int> _ip = [
  58,
  50,
  42,
  34,
  26,
  18,
  10,
  2,
  60,
  52,
  44,
  36,
  28,
  20,
  12,
  4,
  62,
  54,
  46,
  38,
  30,
  22,
  14,
  6,
  64,
  56,
  48,
  40,
  32,
  24,
  16,
  8,
  57,
  49,
  41,
  33,
  25,
  17,
  9,
  1,
  59,
  51,
  43,
  35,
  27,
  19,
  11,
  3,
  61,
  53,
  45,
  37,
  29,
  21,
  13,
  5,
  63,
  55,
  47,
  39,
  31,
  23,
  15,
  7,
];

const List<int> _fp = [
  40,
  8,
  48,
  16,
  56,
  24,
  64,
  32,
  39,
  7,
  47,
  15,
  55,
  23,
  63,
  31,
  38,
  6,
  46,
  14,
  54,
  22,
  62,
  30,
  37,
  5,
  45,
  13,
  53,
  21,
  61,
  29,
  36,
  4,
  44,
  12,
  52,
  20,
  60,
  28,
  35,
  3,
  43,
  11,
  51,
  19,
  59,
  27,
  34,
  2,
  42,
  10,
  50,
  18,
  58,
  26,
  33,
  1,
  41,
  9,
  49,
  17,
  57,
  25,
];

const List<int> _e = [
  32,
  1,
  2,
  3,
  4,
  5,
  4,
  5,
  6,
  7,
  8,
  9,
  8,
  9,
  10,
  11,
  12,
  13,
  12,
  13,
  14,
  15,
  16,
  17,
  16,
  17,
  18,
  19,
  20,
  21,
  20,
  21,
  22,
  23,
  24,
  25,
  24,
  25,
  26,
  27,
  28,
  29,
  28,
  29,
  30,
  31,
  32,
  1,
];

const List<int> _p = [
  16,
  7,
  20,
  21,
  29,
  12,
  28,
  17,
  1,
  15,
  23,
  26,
  5,
  18,
  31,
  10,
  2,
  8,
  24,
  14,
  32,
  27,
  3,
  9,
  19,
  13,
  30,
  6,
  22,
  11,
  4,
  25,
];

const List<int> _pc1 = [
  57,
  49,
  41,
  33,
  25,
  17,
  9,
  1,
  58,
  50,
  42,
  34,
  26,
  18,
  10,
  2,
  59,
  51,
  43,
  35,
  27,
  19,
  11,
  3,
  60,
  52,
  44,
  36,
  63,
  55,
  47,
  39,
  31,
  23,
  15,
  7,
  62,
  54,
  46,
  38,
  30,
  22,
  14,
  6,
  61,
  53,
  45,
  37,
  29,
  21,
  13,
  5,
  28,
  20,
  12,
  4,
];

const List<int> _pc2 = [
  14,
  17,
  11,
  24,
  1,
  5,
  3,
  28,
  15,
  6,
  21,
  10,
  23,
  19,
  12,
  4,
  26,
  8,
  16,
  7,
  27,
  20,
  13,
  2,
  41,
  52,
  31,
  37,
  47,
  55,
  30,
  40,
  51,
  45,
  33,
  48,
  44,
  49,
  39,
  56,
  34,
  53,
  46,
  42,
  50,
  36,
  29,
  32,
];

const List<int> _shifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1];

const List<List<List<int>>> _sbox = [
  [
    [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7],
    [0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8],
    [4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0],
    [15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
  ],
  [
    [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10],
    [3, 13, 4, 7, 15, 2, 8, 14, 12, 0, 1, 10, 6, 9, 11, 5],
    [0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15],
    [13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
  ],
  [
    [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8],
    [13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1],
    [13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7],
    [1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
  ],
  [
    [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15],
    [13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9],
    [10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4],
    [3, 15, 0, 6, 10, 1, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
  ],
  [
    [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9],
    [14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6],
    [4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14],
    [11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
  ],
  [
    [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11],
    [10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8],
    [9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6],
    [4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
  ],
  [
    [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1],
    [13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6],
    [1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2],
    [6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
  ],
  [
    [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7],
    [1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2],
    [7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8],
    [2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
  ],
];

// ------------------------------------------------- tablas derivadas (1 sola vez)

int _permute(int value, List<int> table, int inBits) {
  var out = 0;
  for (final pos in table) {
    out = (out << 1) | ((value >> (inBits - pos)) & 1);
  }
  return out;
}

int _permute32(int value, List<int> table) {
  var out = 0;
  for (final pos in table) {
    out = (out << 1) | ((value >> (32 - pos)) & 1);
  }
  return out;
}

/// Convierte una tabla de permutación (posiciones 1..64) en 8 tablas por byte.
List<List<int>> _byteTables64(List<int> table) {
  final tables = List<List<int>>.generate(8, (_) => List<int>.filled(256, 0));
  for (var j = 0; j < 64; j++) {
    final src = table[j] - 1;
    final byteIndex = src >> 3;
    final bitInByte = 7 - (src & 7);
    for (var b = 0; b < 256; b++) {
      if ((b >> bitInByte) & 1 == 1) {
        tables[byteIndex][b] |= 1 << (63 - j);
      }
    }
  }
  return tables;
}

/// Expansión E en 4 tablas (una por byte de la mitad derecha).
List<List<int>> _buildExpansion() {
  final tables = List<List<int>>.generate(4, (_) => List<int>.filled(256, 0));
  for (var j = 0; j < 48; j++) {
    final src = _e[j] - 1;
    final byteIndex = src >> 3;
    final bitInByte = 7 - (src & 7);
    for (var b = 0; b < 256; b++) {
      if ((b >> bitInByte) & 1 == 1) tables[byteIndex][b] |= 1 << (47 - j);
    }
  }
  return tables;
}

/// S-box + permutación P combinadas: 8 tablas de 64 entradas.
List<List<int>> _buildSp() {
  final sp = List<List<int>>.generate(8, (_) => List<int>.filled(64, 0));
  for (var i = 0; i < 8; i++) {
    for (var g = 0; g < 64; g++) {
      final row = ((g >> 4) & 2) | (g & 1);
      final col = (g >> 1) & 0xF;
      final v = _sbox[i][row][col];
      sp[i][g] = _permute32(v << (28 - 4 * i), _p);
    }
  }
  return sp;
}

final List<List<int>> _ipTable = _byteTables64(_ip);
final List<List<int>> _fpTable = _byteTables64(_fp);
final List<List<int>> _expandTable = _buildExpansion();
final List<List<int>> _sp = _buildSp();

// ------------------------------------------------------------- proceso de clave

List<int> _subkeys(List<int> key8) {
  var k = 0;
  for (final b in key8) {
    k = (k << 8) | b;
  }
  final cd = _permute(k, _pc1, 64);
  var c = (cd >> 28) & 0x0FFFFFFF;
  var d = cd & 0x0FFFFFFF;
  final keys = List<int>.filled(16, 0);
  for (var i = 0; i < 16; i++) {
    final s = _shifts[i];
    c = ((c << s) | (c >> (28 - s))) & 0x0FFFFFFF;
    d = ((d << s) | (d >> (28 - s))) & 0x0FFFFFFF;
    keys[i] = _permute((c << 28) | d, _pc2, 56);
  }
  return keys;
}

// ---------------------------------------------------------------- bloque DES

int _desBlock(int block, List<int> keys, {bool decrypt = false}) {
  final b = Uint8List(8)
    ..[0] = (block >> 56) & 0xFF
    ..[1] = (block >> 48) & 0xFF
    ..[2] = (block >> 40) & 0xFF
    ..[3] = (block >> 32) & 0xFF
    ..[4] = (block >> 24) & 0xFF
    ..[5] = (block >> 16) & 0xFF
    ..[6] = (block >> 8) & 0xFF
    ..[7] = block & 0xFF;

  final permuted =
      _ipTable[0][b[0]] |
      _ipTable[1][b[1]] |
      _ipTable[2][b[2]] |
      _ipTable[3][b[3]] |
      _ipTable[4][b[4]] |
      _ipTable[5][b[5]] |
      _ipTable[6][b[6]] |
      _ipTable[7][b[7]];

  var left = (permuted >> 32) & 0xFFFFFFFF;
  var right = permuted & 0xFFFFFFFF;

  for (var round = 0; round < 16; round++) {
    final k = decrypt ? keys[15 - round] : keys[round];
    final expanded =
        _expandTable[0][(right >> 24) & 0xFF] |
        _expandTable[1][(right >> 16) & 0xFF] |
        _expandTable[2][(right >> 8) & 0xFF] |
        _expandTable[3][right & 0xFF];
    final x = expanded ^ k;
    final f =
        _sp[0][(x >> 42) & 63] |
        _sp[1][(x >> 36) & 63] |
        _sp[2][(x >> 30) & 63] |
        _sp[3][(x >> 24) & 63] |
        _sp[4][(x >> 18) & 63] |
        _sp[5][(x >> 12) & 63] |
        _sp[6][(x >> 6) & 63] |
        _sp[7][x & 63];
    final next = right;
    right = (left ^ f) & 0xFFFFFFFF;
    left = next;
  }

  final pre = (right << 32) | left;
  final out = Uint8List(8)
    ..[0] = (pre >> 56) & 0xFF
    ..[1] = (pre >> 48) & 0xFF
    ..[2] = (pre >> 40) & 0xFF
    ..[3] = (pre >> 32) & 0xFF
    ..[4] = (pre >> 24) & 0xFF
    ..[5] = (pre >> 16) & 0xFF
    ..[6] = (pre >> 8) & 0xFF
    ..[7] = pre & 0xFF;

  return _fpTable[0][out[0]] |
      _fpTable[1][out[1]] |
      _fpTable[2][out[2]] |
      _fpTable[3][out[3]] |
      _fpTable[4][out[4]] |
      _fpTable[5][out[5]] |
      _fpTable[6][out[6]] |
      _fpTable[7][out[7]];
}

int _readBlock(Uint8List data, int offset) {
  var v = 0;
  for (var i = 0; i < 8; i++) {
    v = (v << 8) | data[offset + i];
  }
  return v;
}

void _writeBlock(Uint8List out, int offset, int value) {
  for (var i = 7; i >= 0; i--) {
    out[offset + i] = value & 0xFF;
    value >>= 8;
  }
}

// ------------------------------------------------------------------- API 3DES

/// Normaliza la clave a 24 bytes (DESedeKeySpec repite el patrón).
Uint8List key24(List<int> key) {
  if (key.isEmpty) throw ArgumentError('clave vacia');
  final out = Uint8List(24);
  for (var i = 0; i < 24; i++) {
    out[i] = key[i % key.length];
  }
  return out;
}

/// Bloque de 8 bytes con 3DES (EDE).
int _tripleBlock(
  int block,
  List<int> k1,
  List<int> k2,
  List<int> k3, {
  bool decrypt = false,
}) {
  if (decrypt) {
    var v = _desBlock(block, k3, decrypt: true);
    v = _desBlock(v, k2);
    return _desBlock(v, k1, decrypt: true);
  }
  var v = _desBlock(block, k1);
  v = _desBlock(v, k2, decrypt: true);
  return _desBlock(v, k3);
}

Uint8List _pkcs5Pad(Uint8List data) {
  final padLength = 8 - (data.length % 8);
  final out = Uint8List(data.length + padLength)..setAll(0, data);
  out.fillRange(data.length, out.length, padLength);
  return out;
}

Uint8List _pkcs5Unpad(Uint8List data) {
  if (data.isEmpty) return data;
  final n = data.last;
  if (n < 1 || n > 8) return data;
  for (var i = 0; i < n; i++) {
    if (data[data.length - 1 - i] != n) return data;
  }
  return Uint8List.sublistView(data, 0, data.length - n);
}

/// Cifra bytes con DESede/ECB/PKCS5Padding.
Uint8List encrypt(List<int> data, List<int> key) {
  final k = key24(key);
  final k1 = _subkeys(k.sublist(0, 8));
  final k2 = _subkeys(k.sublist(8, 16));
  final k3 = _subkeys(k.sublist(16, 24));
  final padded = _pkcs5Pad(Uint8List.fromList(data));
  final out = Uint8List(padded.length);
  for (var offset = 0; offset < padded.length; offset += 8) {
    _writeBlock(
      out,
      offset,
      _tripleBlock(_readBlock(padded, offset), k1, k2, k3),
    );
  }
  return out;
}

/// Descifra bytes con DESede/ECB/PKCS5Padding (sin el padding).
Uint8List decrypt(List<int> data, List<int> key) {
  if (data.length % 8 != 0) {
    throw ArgumentError('longitud no multiplo de 8');
  }
  final k = key24(key);
  final k1 = _subkeys(k.sublist(0, 8));
  final k2 = _subkeys(k.sublist(8, 16));
  final k3 = _subkeys(k.sublist(16, 24));
  final input = Uint8List.fromList(data);
  final out = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += 8) {
    _writeBlock(
      out,
      offset,
      _tripleBlock(_readBlock(input, offset), k1, k2, k3, decrypt: true),
    );
  }
  return _pkcs5Unpad(out);
}

// ------------------------------------------------- compatibilidad con el APK

String _hexOfAscii(String s) {
  final buffer = StringBuffer();
  for (final code in s.codeUnits) {
    buffer.write(code.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

String _asciiOfHex(String hex) {
  if (hex.length.isOdd) throw ArgumentError('hex impar');
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return String.fromCharCodes(bytes);
}

/// Cuerpo tal como lo espera el portal: `hex(ascii(base64(cifrado)))`.
String encryptLikeApp(String plain, List<int> key) {
  final cipher = encrypt(utf8.encode(plain), key);
  return _hexOfAscii(base64.encode(cipher));
}

/// Descifra el `data` de una respuesta del portal.
String decryptLikeApp(String hexBody, List<int> key) {
  final b64 = _asciiOfHex(hexBody);
  final cipher = base64.decode(b64);
  return utf8.decode(decrypt(cipher, key), allowMalformed: true);
}
