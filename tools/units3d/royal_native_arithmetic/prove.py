"""Read-only Godot-process capture and exact scalar-value proof. No numerical fitting."""
import argparse
from fractions import Fraction as F
import hashlib
import json
from math import comb, factorial, isqrt
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
SCHEMA = "royal-native-arithmetic/1"
MAC_ID = "a3fb340f3ed530f48b649d5860f64d35"
MAC_PROFILE = {
    "sin": {
        "code_offset": 2368,
        "entry_offset": 2416,
        "code": (
            "182d4454fb21e93f407ae53b0100204183c8c96d305fe43f00004454fb21f93f00004c4c238c863d457370032e8a293b"
            "7f2303d5fd7bbfa9fd0300910820601e01c0601e800a0054c2fdff5cea031faa2020621ea2fdff5c8d3600542020621e"
            "0900f0d2ab0600540000669e0100298a21fc74d321fc0fd13f0010f1a00800540a00098a292d00aadefaff1020fc46d3"
            "211440f2de0f00cba0040054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a8424c09ac60004aa6420c19a"
            "6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b2100029a22f47ed34a0101ca"
            "430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1e30303cb2120c29a0324c39a"
            "210003aac43400545f010014c313c1a8c51b40a9e7ffff17c0f6ff100414c16c061c406d0108641e2240641e2000609e"
            "4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f22af9008a013600546d010014"
            "01106e1efd7bc1a8ff0f5fd62138611e0038601efd7bc1a8ff0f5fd67f2303d5fd7bbfa9fd03009100c0601ea2f2ff5c"
            "ea031faa0020621e82f2ff5cad3300540020621e0900f0d26b0600540000669e01fc74d321fc0fd13f0010f1a0fdff54"
            "292d00aafeefff1020fc46d3211440f2de0f00cba0040054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a"
            "8424c09ac60004aa6420c19a6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b"
            "2100029a22f47ed32a0401ca430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1"
            "e30303cb2120c29a0324c39a210003aae529005408010014c313c1a8c51b40a9e7ffff17e0ebff100414c16c061c406d"
            "0108641e2240641e2000609e4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f2"
            "0a0440ca4a0141d3002b0054150100147f2303d5fd7bbfa9fd0300910820601e01c0601e60f4ff5442e8ff5cea031faa"
            "2020621e22e8ff5c6d0b00542020621e0900f0d2cb0700540000669e0100298a21fc74d321fc0fd13f0010f100f3ff54"
            "0a00098a292d00aa5ee5ff1020fc46d3211440f2de0f00cbc0050054c20fc1a8c41740a9200001d1e00300cba620c19a"
            "8520c19a8424c09ac60004aa6420c19a6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002ab"
            "c27c099b2100029a22f47ed34b0101ca2c0401ca430401ca42fc7f93210002ca21f04092000002ca7f0000f12210c0da"
            "430001d1e30303cb2120c29a0324c39a210003aac40000548a014192f50000940140601e6a014192af0000148a014192"
            "aa0000940140601e6a014192f0000014c313c1a8c51b40a9deffff1720e0ff100414c16c061c406d0108641e2240641e"
            "2000609e4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671e1f0040f2a10000542af9008a"
            "f40000940140601eb60000140a0440ca4a0141d3ad0000940140601e4a0141d2f2000014e703679e0640601ef5ffff17"
            "7f2303d5fd7bbfa9fd0300910820601e01c0601e00e8ff5442dbff5cea031faa4020611e22dbff5c2c0700542020621e"
            "0900f0d22b0b00540000669e0100298a21fc74d321fc0fd13f0010f120e6ff540a00098a292d00aa5ed8ff1020fc46d3"
            "211440f2de0f00cb20090054c20fc1a8c41740a9200001d1e00300cba620c19a8520c19a8424c09ac60004aa6420c19a"
            "6324c09a650005aa4224c09a440004aa807cc99ba27c099ba17cc99b000002abc27c099b2100029a22f47ed34a0501ca"
            "430401ca4a01419242fc7f93210002ca21f04092000002ca7f0000f12210c0da430001d1e30303cb2120c29a0324c39a"
            "210003aa60070058017cc19b200c439e402c4cd31000679e0084f07ee3060010420f00100108601e620cc16c5044c16c"
            "230c421f3144501f6414c16c524cc16c2410431f3248511f2514441f334c521f620cc16c5044c16c2208451f3040531f"
            "230c421f3144501f2208631e500040fd430d084e3040511f0000421f11106e1e001c236e3144501f214e601e024c711e"
            "2018621efd7bc1a8ff0f5fd6c313c1a8c51b40a9c3ffff17c0cfff100414c16c061c406d0108641e2240641e2000609e"
            "4508651e4108661e4708671e0038651e0638611e0238661e4238611e4738671ec028671eeaff00abcdffff171f2003d5"
            "35c26821a2da0fc9cd9cd11ffdd8e53d5d1f29a9e5e55abea1487d56e31dc73e03dfbf19a0012abfd0f710111111813f"
            "485555555555c5bf7f2303d5fd7bbfa9fd030091e0fdff58047cc19b800c439e402c4cd31000679e0084f07e63fdff10"
            "1f08601e620cc16c803c509284bc4092e30f421f6414c16c060c439ee413431f870c439ee517441f620cc16ce20b451f"
            "c684f07ee30f421fe784f07eff0b631e430d084e001c5f1f0028661e001c236efd7bc1a8ff0f5fd67f2303d5fd7bbfa9"
            "fd030091030000140740601ee603679ec028671ea3f9ff101f08601e620cc16ce30f421f6414c16ce413431fe517441f"
            "620cc16ce20b451fe30f421fff0b631e430d084e001c5f1f0028661e001c236efd7bc1a8ff0f5fd69b1a86a049faa8bd"
            "053f4e7b"
        ),
    },
    "sinf": {
        "code_offset": 12632,
        "entry_offset": 12632,
        "code": (
            "7f2303d5fd7bbfa9fd0300910000261e00780012231600181f00036b23160018620500541f00036b0309005400c0221e"
            "0216005c0208621e4000609e4240641ec415005c4180441f1f0040f200fc41d3000041d30002005481150010220c406d"
            "2108611e2414416d230c421f2514441f2208611e06106e1e4314431f2018431f0100679e001c212e0040621efd7bc1a8"
            "ff0f5fd6a11400103044406d2408611e2508641e320840fd9144501f8608651eb204521fc048511f0100679e001c212e"
            "0040621efd7bc1a8ff0f5fd6431000181f00036b6206005400c0221e007c185300000151211400102010008b0414406d"
            "0408641e0508651e83a8614e8140641e63547f4f8438611e8028651e031c232e0008601e60110010042cdf0c020040fd"
            "0428641e0528651e0618441f071c451f6608661e4708671ec008671e0040621efd7bc1a8ff0f5fd6e30c00181f00036b"
            "c3010054a10e001001c0221e3044406d2408611e2508641e320840fd9144501f8608651eb204521fc048511f0040621e"
            "fd7bc1a8ff0f5fd6220b001ce40a001c0000021f0008241efd7bc1a8ff0f5fd60038201efd7bc1a8ff0f5fd67f2303d5"
            "fd7bbfa9fd0300910000261e00780012c30800181f00036be3080018820400541f00036b6306005400c0221ea208005c"
            "0208621e4000609e4040641e4138601e2008611e0004084e812b001022acdf4c24acdf4c02d4624e03d4634e2108641e"
            "8144186e267c404c05cc624e06cc634e20dc656e00dc666e0068610e1f007ff24000005400f8a02e1f0040f2a0000054"
            "0140211e00040c5efd7bc1a8ff0f5fd601040c5efd7bc1a8ff0f5fd6c30300181f00036b0203005400c0221e0028601e"
            "007c185300000151810700102010008b0414406d0408641e0508651e8000609e8140641e8438611e8128651ed5ffff17"
            "6202001c2402001c01c0201e4138211e2108241e0000021f0008241efd7bc1a8ff0f5fd60038201e0104045efd7bc1a8"
            "ff0f5fd60000807f0000f0420000804cdb0f493f00008039000080320000804c83c8c96d305fe43f182d4454fb21f93f"
            "075c143326a6913c4a8f93fc6991f93ef45d94167fc056bf999689c75355a53f972eb8fcffffdfbf8f81c40f3e9429bf"
            "eb45d1af7310813f2aa068525455c5bf"
        ),
    },
    "acosf": {
        "code_offset": 47920,
        "entry_offset": 47920,
        "code": (
            "7f2303d5fd7bbfa9fd03009101c0201e02102e1e2020221e02102c1ec50600542020221e6208001c2c0100542020221e"
            "ca030054e108005c00c0221e2038601e0040621efd7bc1a8ff0f5fd602102e1e4138211e21c0221e40080010020c406d"
            "0414416d061c426d30c0611e230c421f2514441f271c461f2208611e4514431f471c451f0820201e8c000054e105005c"
            "e084501f02000014e008701e0040621efd7bc1a8ff0f5fd640070010020c406d0414416d061c426d00c0221e0108601e"
            "230c421f2514441f271c461f2208611e4514431f471c451f2108671e0000411f8103005c2038601e0040621efd7bc1a8"
            "ff0f5fd6600000542c010054260100540820201ee103679ec201005c20cc621e0040621efd7bc1a8ff0f5fd68000001c"
            "0038201efd7bc1a8ff0f5fd60000807f0000003b1f2003d51f2003d51f2003d500000044fb210940182d4454fb210940"
            "182d4454fb21f93f0000000000000000537095b23ce95e3f1068a86d1840613f8b5da3a05f7e803f3221e814ec219b3f"
            "9e3f17c38c2bbe3fe1c6c7649ea0f63f"
        ),
    },
}


# Actual Ubuntu Godot-process code and operands; semantics are checked below.
LINUX_ID = "cfae91b4a956116b64e2a41607671c1eeb3cc292"
LINUX_PROFILE = {
    'sin': {
        'code_offset': 449552,
        'entry_offset': 449552,
        'code': (
            'f30f1efa554889e54883ec3064488b042528000000488945f831c0c5f8ae5de88b55e889d080e49f8945f0c4e1f97ec0'
            '48c1f82025ffffff7f81e2006000000f850b0400003dffff4f3e7f34c5f9540d8c5c0200c5fb10152cf00200c5f92fd1'
            '7604c5fb59c8488b45f864482b0425280000000f850a070000c9c30f1f44000031c93dff5feb3f0f8f0b010000c5f954'
            '0d4b5c0200c5fb101523130300c5f92fd10f8759030000c5e957d2c5fb10351d5c0200c5fb102535130300488d350e4d'
            '0600c5fbc2da06c4e3494bf230c5fb101d13130300c5f358d3c5eb5cdbc4e1f97ed0c1e0024863f8448d4003c5f35ccb'
            'c5fb1014fe8d780283c0014d63c048984863ffc5f359e9c4e2d1a925e8120300c5f359ddc4e2c999dcc5fb1025df1203'
            '00c4e2d1a925de120300c4e2d1a9258dee0200c5e358d9c5db59e5c4e2d999cec4a17b1024c6c4e2e1a924c6c4e2d99d'
            'cac4e2f1991cfec5fa7e0d715b0200c5e358dac5f155dbc5f154c8c5e156c184c90f84effeffffc5f8ae5de48b45e480'
            'e49f09d08945e4c5f8ae55e4e9d5feffff0f1f80000000003dfc6803400f8fe5000000c5f95415355b0200c5fb100d2d'
            'ef0200c5f35ccac5e957d2c5f92fd10f87db020000c5fb10253bf20200c5f1540d0b5b0200c5fb101d0b120300488d35'
            'ec4b0600c5fb102d04120300c5f358d3c5eb5cdbc4e1f97ed0c1e0028d78024c'
        ),
        'extra_code': [
            {
                'bytes': (
                    'c5fb59d0c5fb100dbc0f0300c5e157dbc4e2e9a90db70f0300c4e2e9a90db60f0300c4e2e9a90db50f0300c4e2e9a90d'
                    'dc0c0300c4e2f9a90d93580200c4e2e199d1c5eb58c0e924fdffff0f1f440000c5f8ae55f03dffff4f3e7f54c5f9540d'
                    '7c580200c5fb10151cec0200c5f92fd10f8601fdffffc5fb59c8e9f8fcffff903dffffef7f0f8ef50000003d0000f07f'
                    '0f845a010000c5fb5ec0e9d0fcffff90c5fb1025100f0300e920fdffff0f1f00b901000000e9c8fbffff660f1f440000'
                    'c5e957d2c5f928d9c5f1570d00580200c5dbc2d201c4e3614bc920c5fb101d050f0300c5fb58d3c5eb5cdbc5fb5cc3c5'
                    'fb58c9c5f359d9c5fb1025f10e0300c4'
                ),
                'offset': 450576,
            },
        ],
        'operands': [
            {
                'bytes': 'ffffffffffffff7f0000000000000000',
                'count': 16,
                'offset': 604400,
            },
            {
                'bytes': '0000000000001000',
                'count': 8,
                'offset': 642200,
            },
            {
                'bytes': '54e3a59bc420c03f',
                'count': 8,
                'offset': 651216,
            },
            {
                'bytes': '0000000000000080',
                'count': 8,
                'offset': 604384,
            },
            {
                'bytes': '2f8729e81011813f',
                'count': 8,
                'offset': 651264,
            },
            {
                'bytes': '000000000000c842',
                'count': 8,
                'offset': 651256,
            },
            {
                'bytes': '155555555555c5bf',
                'count': 8,
                'offset': 651272,
            },
            {
                'bytes': '39e2d9ed6bc1563f',
                'count': 8,
                'offset': 651280,
            },
            {
                'bytes': '355555555555a5bf',
                'count': 8,
                'offset': 651288,
            },
            {
                'bytes': '000000000000e03f',
                'count': 8,
                'offset': 642000,
            },
            {
                'bytes': '182d4454fb21f93f',
                'count': 8,
                'offset': 642288,
            },
            {
                'bytes': '075c143326a6913c',
                'count': 8,
                'offset': 643096,
            },
            {
                'bytes': '59dffcc2ffdd5abe',
                'count': 8,
                'offset': 651224,
            },
            {
                'bytes': 'd97e9a7be21dc73e',
                'count': 8,
                'offset': 651232,
            },
            {
                'bytes': 'b808db19a0012abf',
                'count': 8,
                'offset': 651240,
            },
            {
                'bytes': 'ce0e11111111813f',
                'count': 8,
                'offset': 651248,
            },
            {
                'bytes': '555555555555c5bf',
                'count': 8,
                'offset': 650528,
            },
            {
                'bytes': '075c143326a691bc',
                'count': 8,
                'offset': 651208,
            },
            {
                'bytes': (
                    '36ee86eeaeeabf3f3bf0c6bcb2fc4abcd35b7d5215c0ef3fb8ef9450f3688b3cd171dd8d37f3c03f9e0f4f7268846d3c'
                    '9506fe2bdbb7ef3fb15af6f4ad1d823cafceafd7d3f0c13fa569970995ef66bcd34b3c2622afef3f69273a13ce2a55bc'
                    '8fb84a5e28eec23f58e0de050f4d6ebcf2361c64eaa5ef3f7ccc17eda64d403ccb665d2c31ebc33f91cb666b667d643c'
                    '28c47c0a349cef3f62743b066b5b8c3c7bf2c54deae7c43ffc72c02adb49593c014d3740ff91ef3f4c9e3a4d3fd067bc'
                    'f326a1cf4fe4c53fb6893f0643f466bcf6ec1e2e4c87ef3f162b33e114658cbc4c4d5ac05de0c63f40c9818b5c2cd3bb'
                    '24defffe1a7cef3fb14075c45bf578bcb5f2ba2f10dcc73fc3973ce250ab453c1cce9edf6b70ef3fb4dc360cc89886bc'
                    '44a9fa2e63d7c83f53b9cb62a20f62bccd2ab8fe3e64ef3fac28fec10ab0763c12c3ced052d2c93f7d13b1803dc4593c'
                    '9767ff8c9457ef3fd5b1033e0d3a6e3c65077a29dbccca3febcdd6573b8859bc793a1ebd6c4aef3f57bbaeedf03d813c'
                    '9961dc4ef8c6cb3fab0c7b6aa5c1693c6ed1b3c3c73cef3f94348ad23a1a62bca3898258a6c0cc3f6b7cc89bd06868bc'
                    'edff53d7a52eef3f83d5565f21c48c3cd0a5b55fe1b9cd3fc26fccd6202e63bc9f6486300720ef3f4b98c11604947b3c'
                    'a3e58a7fa5b2ce3feb2c57af06be60bc3b87c509ec10ef3f83122c7672908d3c7715f3d4eeaacf3fb8328e50885d61bc'
                    'a1ee7d9f5401ef3ffdcae5991e3c8d3c5c1565bf5c51d03fc88efd9dc2b879bc262f0d3041f1ee3f72d3de081baa82bc'
                    '3664f3ce00cdd03fb5e2930c0afb79bc1cf1c0fbb1e0ee3fb1c3bb8023fd4bbcebdd94aa6148d13fa415b6b581e86bbc'
                    'a1efd544a7cfee3fd041f54a0a6d55bc76b8c6647dc3d13ff5cf0dfe7660743ca8ef764f21beee3f3e54ba129f2f80bc'
                    '36af1a11523ed23f18ff4e3380f074bc4fafbb6120acee3f8d65943ed5c1623c9fb43ec4ddb8d23f07d8f2993855613c'
                    '83cda7c3a499ee3fe83cc51b4b2682bc879f04941e33d33f2c300cb4b60c7e3ceda929bfae86ee3fa758bbfd7a39893c'
                    'd8d3699712add33f98838704553d003c403d19a03e73ee3f13ce46358b4286bc97e69ee6b726d43f9fc50557c7097fbc'
                    'd0e936b4545fee3fbcc82fd00feb873c203d0f9b0ca0d43fad8eb06bba23783c9c442a4bf14aee3f33688a2ea08c86bc'
                    '7aa768cf0e19d53ff3f0ee5571357b3ca5d680b61436ee3f375201aa937772bc97f5a29fbc91d53fcbe03fac4bc7673c'
                    'c1d6ac49bf20ee3f6c63efc7ae6056bc75870729140ad63f3391a80bd81f5b3ccedb035af10aee3fe61a7702e7e85f3c'
                    'f7d7388a1382d63fad4a440292887dbc5e87bd3eabf4ed3fc436677e8a2d8ebc55023ae3b8f9d63f0ddae94ec12b743c'
                    'd628f250eddded3fbfa22bd4c8806ebc144276550271d73fceb64b31d7ea66bc125999ebb7c6ed3f35cd6d7764b3543c'
                    '4e6dc803eee7d73ff25abfdabc637bbc838e886b0bafed3fea5c5e2b9e248a3c496982127a5ed83fe0ac5f9b0ea4783c'
                    'dca9712fe896ed3f9d03d2d51bf68f3c2f9974a7a4d4d83f266376ea024a743c4a7be1974e7eed3f94ed2b3570b763bc'
                    'c546f5e96b4ad93f583f683ee19c76bc40403e073f65ed3f37ec4b43366287bc1005e802cebfd93fa4b020a3399e703c'
                    'e019c6e1b94bed3f618f8577bb348f3cca0cc51cc934da3fcdce503b0e315abc067c8d8dbf31ed3fddcb8930dd607e3c'
                    '7792a0635ba9da3f81033cb13e2966bcf0947d725017ed3f8ea4c11e2bd5803c17163205831ddb3f19f599cb42e27abc'
                    '9fad52fa6cfcec3f0d2a8f50b5b5883c43acdb303e91db3ff13f6c2fad387ebce5829a9015e1ec3f9a1031bb39f1813c'
                    'a340b1178b04dc3fa79f7e75e69f613c2e97b2a24ac5ec3f983aa82b16ee643c9ed17fec6777dc3f26583d1a4db15ebc'
                    '0b7dc69f0ca9ec3f62345e48816a64bc1fa5d4e3d2e9dc3f98e2da128afc62bc841acef85b8cec3f230159a1d1b37a3c'
                    '61760434ca5bdd3f9cc25fa7448a723c3be58b20396fec3f42dbaafbdb4187bc9a9c32154ccddd3f9afd71e1c6d4703c'
                    '5e178b8ba451ec3f80a89a3bb4bb61bc692a58c1563ede3f8ff8991082a450bc81dd1db09e33ec3fc0c582eef5aa8cbc'
                    'f0054b74e8aede3f7d029b3cb48957bc507d5b062815ec3f28e81213119288bc'
                ),
                'count': 1568,
                'offset': 863200,
            },
        ],
    },
    'sinf': {
        'code_offset': 525936,
        'entry_offset': 525936,
        'code': (
            'f30f1efac5f97ec2c5fa5ad089d0c1e81425ff0700003df30300007743c5eb59ca3d970300000f86e4000000c5eb59d9'
            'c5fb100558450500c4e2f1a9053f450500c5f359cbc4e2e9991d22450500c4e2e199c1c5fb5ac0c30f1f840000000000'
            'c5f057c93d2e0400000f87b1000000c5eb5905d9440500488d0db2440500488d5170c5fb2cc00500008000c1f818c5f3'
            '2ac8a802c4e2e99d0dbb440500480f44d1c5f359d1a801752f83e003c5fb104260c4e2e9a94250c5f3590cc1c5eb59d9'
            'c5eb59d3c4e2f1995a40c4e2e199c2c5fb5ac0c30f1f4000c5eb59cac5fb104268c5fb106230c4e2e9a94258c5eb59d9'
            'c4e2d9995238c4e2e9994a48c4e2f199c3c5fb5ac0c3662e0f1f84000000000081e20000807f0f84e1000000c30f1f00'
            '3df70700000f87cd00000089d189d04c8d059a43050089d6c1e91a25ffff7f00c1ee1783e10f0d0000800083e607c1ea'
            '1f498d3c88c4e249f7f04189f18b4720450faf0c888b4f1048bf00000000000000c0480fafc6480fafce4c0facc82048'
            '01c848b900000000000000204801c14889ce4821f94829c848c1ee3ec4e1f32ac8c5f3590547f0010001f2488d05ee43'
            '0500f6c202488d4890480f44c183e601c5fb59d075424863d2c5fb590cd1c5fb104060c4e2e9a94050c5eb59d9c5eb59'
            'd3c4e2f1995840c4e2e199c2e9defeffff0f1f8000000000e9e35b0000c5f35a'
        ),
        'extra_code': [
            {
                'bytes': 'ff0f1f8000000000e9e35b0000c5f35ac9c3660f1f440000c5eb59cac5fb104068c5fb106830c4e2e9a94058c5eb59d9',
                'offset': 526432,
            },
        ],
        'operands': [
            {
                'bytes': '24cf7437eb9429bf',
                'count': 8,
                'offset': 871424,
            },
            {
                'bytes': 'c40b23057610813f',
                'count': 8,
                'offset': 871408,
            },
            {
                'bytes': '03a695595455c5bf',
                'count': 8,
                'offset': 871392,
            },
            {
                'bytes': '83c8c96d305f6441',
                'count': 8,
                'offset': 871360,
            },
            {
                'bytes': '182d4454fb21f93f',
                'count': 8,
                'offset': 871368,
            },
            {
                'bytes': '182d4454fb21193c',
                'count': 8,
                'offset': 653408,
            },
        ],
    },
    'acosf': {
        'code_offset': 98288,
        'entry_offset': 98288,
        'code': (
            'f30f1efac5f8540d04b90700c5f82e0dfcaf0700770ae9750106000f1f440000488b05a98f0c008338ff74ea55bf0100'
            '00004889e54883ec10c5fa1145fce85da9ffffc5fa104dfcbf65000000c9c5f828c1e989ffffff660f1f840000000000'
            'f30f1efac5fa100da4af0700c5f82ec8770ee949040600660f1f840000000000488b05498f0c008338ff74e6bf810000'
            '00c5f828c8e946ffffff660f1f440000f30f1efac5f8540d64b80700c5f82e0d5caf0700770ae9450606000f1f440000'
            '488b05098f0c008338ff74ea55bf010000004889e54883ec10c5fa1145fce8bda8ffffc5fa104dfcbf66000000c9c5f8'
            '28c1e9e9feffff660f1f840000000000f30f1efac5e857d2ba00000000c5f82eca0f9bc00f45c284c0740ec5f82ec20f'
            '9bc00f45c284c07557554889e54883ec10c5fa114df8c5fa1145fce8b0080600c5e057dbba00000000c5f82ec30f9bc0'
            '0f45c284c0741dc5fa1055fcba01000000c5fa104df8c5f82ed30f9ac00f45c284c07524c9c3662e0f1f840000000000'
            '488b05498e0c008b0085c07433e95e080600660f1f440000c5f0540d70b70700c5fa1015c4ae0700c5f82ed172c6488b'
            '05138e0c0064c70022000000c9c36690bf67000000e916feffff660f1f440000f30f1efac5f8540d34b70700c5f82e0d'
            '2cae0700730ae9350d06000f1f440000488b05d98d0c008338ff74ea31ffc5f8'
        ),
        'extra_code': [
            {
                'bytes': (
                    'c5f97ec03d0000803f74253d000080bf742601c03d000000ff7605c5fa58c0c3c5f857c0e9f7e200000f1f8000000000'
                    'c5f857c0c30f1f00c5fa1005e0af0100c5fa5c05e0af0100c30f1f8000000000f30f1efac5f97ec28d04123dffffff7e'
                    '0f87a2020000c5fa5ad83ddba1c27e0f87b30100003d000000400f8690020000c5e359d3c5fb100d84730200c5fb1005'
                    '8c730200c5fb1035a4730200c57b1005dc730200c4e2e9a9057b730200c4e2e9a90d62730200c4e2e9a93589730200c4'
                    '62e9a905c0730200c5eb59e2c5db59ecc4e2f999ccc5fb100553730200c4e2e9a90552730200c5d359fdc4e2c999c4c5'
                    'fb103559730200c4e2e9a93558730200c4e2f199c5c5fb100d53730200c4e2e9a90d52730200c4e2f199f4c5fb100d4d'
                    '730200c4e2e9a90d4c730200c4e2b999ccc4e2c999cdc4e2f999cfc5f928c1c4e2e1ad0d50730200c4e2e1ad053f7302'
                    '00c5f35ac9c5fb5ac0c5f82ec17a060f84bb0000003dffffff7d0f87b800000081faa38588320f847401000081fa2262'
                    '82390f8498010000c5fb100d304a0200c5e359c2c57b100d7cbb0500c57b100594bb0500c5fb10359cbb0500c462e9a9'
                    '0d5bbb0500c5f35ccbc5fb103d97bb0500c5fb101d5fbb0500c57b101d8fbb0500c4e2e9a91d46bb0500c462e9a9054d'
                    'bb0500c4e2e9a93554bb0500c4e2e9a93d5bbb0500c4e2a199156abb0500c4e2b199dcc4e2b999f4c4e2c199e2c4e2c9'
                    '99e5c4e2e199ecc4e2f19dc5c5fb5ac0c30f1f8000000000c5e1540590b50100c5fb100d70480200c5fa7e1570b50100'
                    'c1ea1fc57b10056dba0500c5fb102575ba0500488d0526440200c5f35cc8c5fb103d72ba0500c462f1a90541ba0500c5'
                    'fb102d71ba0500c5fb103579ba0500c4e2f1a92538ba0500c57b101570ba0500c4e2f1a93d37ba0500c5f351c1c4e2f1'
                    'a92d3aba0500c4e2f1a93541ba0500c5e955c0c5e954d3c5f956c2c5f359d1c4e2a9990d40ba0500c5eb59dac4e2b999'
                    'e2c4e2c199eac4e2c999d1c4e2d199d3c4e2d999dac4e2e1a904d0c5fb5ac0c3c5fa1005d8ac0100c5fa580518ad0100'
                    'c30f1f8000000000e9f3fcffff0f1f00c5fb1005a8480200c5fb5ac0c30f1f00c5fa1005a8ac0100c5fa5805d8ad0100'
                    'c3662e0f1f8400000000000f1f440000c5f97ec03d0000803f741d8d140081fa000000ff771a3d0000807f740fe9bedf'
                    '0000660f1f440000c5f857c0c30f1f00c5fa58c0c366662e0f1f840000000000'
                ),
                'offset': 491824,
            },
        ],
        'operands': [
            {
                'bytes': 'ffffff7f000000000000000000000000',
                'count': 16,
                'offset': 604416,
            },
            {
                'bytes': '0000803f',
                'count': 4,
                'offset': 602112,
            },
            {
                'bytes': 'ffff7f7f',
                'count': 4,
                'offset': 602204,
            },
            {
                'bytes': 'db0f4940',
                'count': 4,
                'offset': 602448,
            },
            {
                'bytes': '00008033',
                'count': 4,
                'offset': 602456,
            },
            {
                'bytes': '9e3003f76d56a83f',
                'count': 8,
                'offset': 652608,
            },
            {
                'bytes': '078083945c55c53f',
                'count': 8,
                'offset': 652624,
            },
            {
                'bytes': '44839904bb6fe53f',
                'count': 8,
                'offset': 652656,
            },
            {
                'bytes': '13f8034774288240',
                'count': 8,
                'offset': 652720,
            },
            {
                'bytes': 'b8ccd9ffffffef3f',
                'count': 8,
                'offset': 652632,
            },
            {
                'bytes': 'fa207c4bed2db33f',
                'count': 8,
                'offset': 652616,
            },
            {
                'bytes': 'a3c9be59c98099bf',
                'count': 8,
                'offset': 652664,
            },
            {
                'bytes': 'f09f526a4bca8ac0',
                'count': 8,
                'offset': 652728,
            },
            {
                'bytes': 'ea11f3e9c3063b40',
                'count': 8,
                'offset': 652640,
            },
            {
                'bytes': '529fc4e4d80314c0',
                'count': 8,
                'offset': 652648,
            },
            {
                'bytes': 'd319cc598a558a40',
                'count': 8,
                'offset': 652672,
            },
            {
                'bytes': 'c7a599274c2782c0',
                'count': 8,
                'offset': 652680,
            },
            {
                'bytes': '1bc61c26b8007240',
                'count': 8,
                'offset': 652688,
            },
            {
                'bytes': '1fc2e2c497ea59c0',
                'count': 8,
                'offset': 652696,
            },
            {
                'bytes': '05010c8c01c24540',
                'count': 8,
                'offset': 652704,
            },
            {
                'bytes': '2822320bbb7d6dc0',
                'count': 8,
                'offset': 652712,
            },
            {
                'bytes': 'a0183154fb21f93f',
                'count': 8,
                'offset': 652744,
            },
            {
                'bytes': '91415754fb21f93f',
                'count': 8,
                'offset': 652736,
            },
            {
                'bytes': '182d4454fb21f93f',
                'count': 8,
                'offset': 642288,
            },
            {
                'bytes': 'dde037333333b33f',
                'count': 8,
                'offset': 867912,
            },
            {
                'bytes': '949028f5dcc6913f',
                'count': 8,
                'offset': 867944,
            },
            {
                'bytes': '96e91526dcf8883f',
                'count': 8,
                'offset': 867960,
            },
            {
                'bytes': '9c5255555555c53f',
                'count': 8,
                'offset': 867904,
            },
            {
                'bytes': '5c66e1ac443f943f',
                'count': 8,
                'offset': 867976,
            },
            {
                'bytes': '06c33ae1721c9f3f',
                'count': 8,
                'offset': 867928,
            },
            {
                'bytes': '731c88df17fb90bf',
                'count': 8,
                'offset': 867984,
            },
            {
                'bytes': '5e46b4b36ddba63f',
                'count': 8,
                'offset': 867920,
            },
            {
                'bytes': 'c46be0eb9ce8963f',
                'count': 8,
                'offset': 867936,
            },
            {
                'bytes': '15637cccbb6d8c3f',
                'count': 8,
                'offset': 867952,
            },
            {
                'bytes': 'e815bfb733587a3f',
                'count': 8,
                'offset': 867968,
            },
            {
                'bytes': 'd6b226c02075a03f',
                'count': 8,
                'offset': 867992,
            },
            {
                'bytes': 'ffffffffffffff7f0000000000000000',
                'count': 16,
                'offset': 604400,
            },
            {
                'bytes': '000000000000f03f',
                'count': 8,
                'offset': 642008,
            },
            {
                'bytes': '0000000000000080',
                'count': 8,
                'offset': 604384,
            },
            {
                'bytes': 'b92dffdd7d2bbe3f',
                'count': 8,
                'offset': 867816,
            },
            {
                'bytes': '44074ecc9529803f',
                'count': 8,
                'offset': 867832,
            },
            {
                'bytes': 'ec8d925a8833503f',
                'count': 8,
                'offset': 867848,
            },
            {
                'bytes': 'cb3b7f669ea0f63f',
                'count': 8,
                'offset': 867808,
            },
            {
                'bytes': 'fd37245dc5c3243f',
                'count': 8,
                'offset': 867864,
            },
            {
                'bytes': 'cb7df6df6bbd0a3f',
                'count': 8,
                'offset': 867880,
            },
            {
                'bytes': 'bc2db47a24279b3f',
                'count': 8,
                'offset': 867824,
            },
            {
                'bytes': '28fad0867e71f1be',
                'count': 8,
                'offset': 867888,
            },
            {
                'bytes': 'eac86e27b0ff653f',
                'count': 8,
                'offset': 867840,
            },
            {
                'bytes': 'c7f823bef211393f',
                'count': 8,
                'offset': 867856,
            },
            {
                'bytes': '61b4d7e177f40a3f',
                'count': 8,
                'offset': 867872,
            },
            {
                'bytes': '2360e46d52fff63e',
                'count': 8,
                'offset': 867896,
            },
            {
                'bytes': '00000033',
                'count': 4,
                'offset': 602368,
            },
            {
                'bytes': 'db0fc93f',
                'count': 4,
                'offset': 602440,
            },
            {
                'bytes': 'b507c93f',
                'count': 4,
                'offset': 602680,
            },
            {
                'bytes': '0000000000000000',
                'count': 8,
                'offset': 640944,
            },
        ],
    },
}

class Rejected(ValueError):
    pass


def require(condition, witness):
    if not condition:
        raise Rejected(witness)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(value).hexdigest()


def file_hash(path):
    with open(path, "rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def binary_image_ids(path):
    """Read UUID/build IDs from the selected file, independently of the collector."""
    raw = Path(path).read_bytes()
    images = []
    if raw[:4] == b"\xca\xfe\xba\xbe":
        count = struct.unpack_from(">I", raw, 4)[0]
        require(count <= 32, "malformed_fat_binary")
        for i in range(count):
            _, _, offset, size, _ = struct.unpack_from(">IIIII", raw, 8 + 20 * i)
            images.append(raw[offset:offset + size])
    else:
        images.append(raw)
    ids = []
    valid_elf = False
    for image in images:
        if image[:4] == b"\xcf\xfa\xed\xfe":
            count = struct.unpack_from("<I", image, 16)[0]
            offset = 32
            for _ in range(count):
                command, size = struct.unpack_from("<II", image, offset)
                require(size >= 8 and offset + size <= len(image), "malformed_macho_command")
                if command == 0x1b:
                    ids.append(image[offset + 8:offset + 24].hex())
                offset += size
        elif image[:6] == b"\x7fELF\x02\x01":
            valid_elf = True
            offset = struct.unpack_from("<Q", image, 32)[0]
            entry_size, count = struct.unpack_from("<HH", image, 54)
            for i in range(count):
                kind, _, fileoff, _, _, size = struct.unpack_from("<IIQQQQ", image, offset + i * entry_size)
                if kind != 4:
                    continue
                cursor, end = fileoff, fileoff + size
                while cursor + 12 <= end:
                    ns, ds, kind = struct.unpack_from("<III", image, cursor)
                    name = image[cursor + 12:cursor + 12 + ns]
                    start = cursor + 12 + ((ns + 3) & ~3)
                    require(start + ds <= end, "malformed_elf_note")
                    if name == b"GNU\x00" and kind == 3:
                        ids.append(image[start:start + ds].hex())
                    cursor = start + ((ds + 3) & ~3)
    require(bool(ids) or valid_elf, "missing_selected_binary_image_id")
    return ids


def floor_log2(x):
    require(x > 0, "nonpositive_log2")
    exponent = x.numerator.bit_length() - x.denominator.bit_length()
    return exponent - (x < F(2) ** exponent)


def up(x):
    require(x >= 0, "negative_error")
    if not x:
        return x
    scale = F(2) ** (95 - floor_log2(x))
    q = x * scale
    return F(-(-q.numerator // q.denominator), 1) / scale


def minnormal(bits):
    require(bits in (24, 53), "unsupported_precision")
    return F(2) ** (-126 if bits == 24 else -1022)


def rnd(bound, bits=53):
    require(0 <= bound < F(2) ** 100, "intermediate_outside_finite_range")
    # Every IEEE direction; an absolute allowance also covers result flushing.
    return up(bound * F(2) ** (1 - bits) + minnormal(bits))


def add_poly(a, b):
    out = [F(0)] * max(len(a), len(b))
    for i, x in enumerate(a):
        out[i] += x
    for i, x in enumerate(b):
        out[i] += x
    return out


def mul_poly(a, b):
    out = [F(0)] * (len(a) + len(b) - 1)
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            out[i + j] += x * y
    return out


class Ball:
    """Exact polynomial plus a uniform absolute error on [-radius,radius]."""
    def __init__(self, poly, error=F(0), radius=F(1, 2)):
        self.p = list(map(F, poly))
        self.e = up(error)
        self.r = radius

    def norm(self):
        return sum(abs(c) * self.r ** i for i, c in enumerate(self.p))

    def mul(self, other, bits=53):
        return self.fma(other, Ball([0], radius=self.r), bits)

    def fma(self, other, addend, bits=53):
        require(self.r == other.r == addend.r, "different_ball_domains")
        poly = add_poly(mul_poly(self.p, other.p), addend.p)
        error = self.norm() * other.e + other.norm() * self.e + self.e * other.e + addend.e
        tiny = minnormal(bits)
        error += tiny * (self.norm() + self.e + other.norm() + other.e) + tiny * tiny + tiny
        value = Ball(poly, error, self.r)
        return Ball(poly, error + rnd(value.norm() + error, bits), self.r)

    def convert(self, bits):
        error = self.e + minnormal(53)
        return Ball(self.p, error + rnd(self.norm() + error, bits), self.r)


def constant(value, radius=F(1, 2)):
    return Ball([value], radius=radius)


def read_memory(profile, offset, count):
    spans = [(profile["code_offset"], profile["code"])]
    spans += [(record["offset"], record["bytes"]) for record in profile.get("extra_code", []) + profile.get("operands", [])]
    for address, hexbytes in spans:
        raw = bytes.fromhex(hexbytes)
        start = offset - address
        if 0 <= start and start + count <= len(raw):
            return raw[start:start + count]
    raise Rejected("operand_outside_capture: " + hex(offset))


def rip_target(profile, pc, displacement_offset, instruction_size, displacement_size=4):
    displacement = int.from_bytes(read_memory(profile, pc + displacement_offset, displacement_size), "little", signed=True)
    return pc + instruction_size + displacement


def coefficients(profile, offset, count):
    # Binary floats are decoded exactly; no host transcendental is used.
    return [F(x) for x in struct.unpack("<" + "d" * count, read_memory(profile, offset, count * 8))]


def positive_acos_bound(h):
    """Bound sqrt(t)*P(t), then conversion to binary32, on t in [0,1/10]."""
    radius = F(1, 10)
    require(h.r == radius and len(h.p) > 0, "acos_domain")
    sqrt_max = F(1, 3)
    sqrt_error = rnd(sqrt_max)
    error = up(h.norm() * sqrt_error + sqrt_max * h.e + sqrt_error * h.e)
    product_max = h.norm() * sqrt_max
    error = up(error + rnd(product_max + error))
    error = up(error + rnd(product_max + error, 24))
    scale = 1 << 120
    n = isqrt(2 * scale * scale)
    sqrt2_lo, sqrt2_hi = F(n, scale), F(n + 1, scale)
    require(sqrt2_lo ** 2 <= 2 <= sqrt2_hi ** 2, "sqrt2_bracket")
    approx = F(0)
    for k, a in enumerate(h.p):
        factor = F(comb(2 * k, k), 8 ** k * (2 * k + 1))
        approx += max(abs(a - sqrt2_lo * factor), abs(a - sqrt2_hi * factor)) * radius ** k
    degree = len(h.p)
    remainder = sqrt2_hi * (radius / 2) ** degree / ((2 * degree + 1) * (1 - radius / 2))
    return up(error + sqrt_max * (approx + remainder)), product_max + error


def mac_bounds(profiles):
    radius = F(1, 2)
    original = Ball([0, 1])
    x = original.fma(constant(1), constant(0))
    z = x.mul(x)
    cs = coefficients(profiles["sin"], 0xfa8, 6)
    h = constant(cs[0])
    for a in cs[1:]:
        h = z.fma(h, constant(a))
    y = x.fma(z.mul(h), original).fma(constant(1), constant(0))
    ideal = [F(0)] * 14
    for k in range(7):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = sum(abs(a - b) * radius ** i for i, (a, b) in enumerate(zip(y.p, ideal)))
    sin_bound = up(y.e + approx + radius ** 15 / factorial(15))

    cs = coefficients(profiles["sinf"], 0x3480, 3)
    x = Ball([0, 1], F(2) ** -126)
    z = x.mul(x)
    x3 = x.mul(z)
    h = z.fma(constant(cs[0]), constant(cs[1]))
    y = z.mul(x3).fma(h, x3.fma(constant(cs[2]), x)).convert(24)
    ideal = [F(0)] * 8
    for k in range(4):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = sum(abs(a - b) * radius ** i for i, (a, b) in enumerate(zip(y.p, ideal)))
    polynomial_bound = up(y.e + approx + radius ** 9 / factorial(9))
    tiny_radius = F(1, 4096)
    x = Ball([0, 1], F(2) ** -126, tiny_radius)
    y = x.fma(constant(F(2) ** 26, tiny_radius), x, 24).mul(constant(F(2) ** -26, tiny_radius), 24)
    tiny_bound = up(y.e + tiny_radius / 2 ** 26 + tiny_radius ** 3 / 6)

    radius = F(1, 10)
    t = Ball([0, 1], radius=radius)
    cs = coefficients(profiles["acosf"], 0xbc90, 6)
    t2 = t.mul(t)
    a = t.fma(constant(cs[0], radius), constant(cs[1], radius))
    b = t.fma(constant(cs[2], radius), constant(cs[3], radius))
    d = t.fma(constant(cs[4], radius), constant(cs[5], radius))
    h = t2.fma(t2.fma(a, b), d)
    require(len(h.p) == 6, "acosf_polynomial_degree")
    acosf_bound, output_max = positive_acos_bound(h)
    require(output_max < F(12, 25), "acosf_output_range")
    require(F(12, 25) * F(513, 512) < F(1, 2), "sine_argument_range")
    return {"sin": sin_bound, "sinf": max(polynomial_bound, tiny_bound), "acosf": acosf_bound}


def linux_sine_bounds(profiles):
    """Arithmetic equations; complete native control/profile validation is separate."""
    sine = profiles["sin"]
    radius = F(13, 100)
    x = Ball([0, 1], radius=radius)
    z = x.mul(x)
    cs = [coefficients(sine, offset, 1)[0] for offset in (0x9efd8, 0x9efe0, 0x9efe8, 0x9eff0, 0x9ed20)]
    h = constant(cs[0], radius)
    for a in cs[1:]:
        h = z.fma(h, constant(a, radius))
    y = z.fma(x.fma(h, constant(0, radius)), constant(0, radius)).fma(constant(1, radius), x)
    ideal = [F(0)] * 12
    for k in range(6):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = Ball(add_poly(y.p, [-v for v in ideal]), radius=radius).norm()
    bounds = [up(y.e + approx + radius ** 13 / factorial(13)), up(F(2) ** -78 / 6 + minnormal(53))]

    # Every possible shifter result, with a uniform interval for each table row.
    big = coefficients(sine, 0x9eff8, 1)[0]
    require(big == F(3) * 2 ** 44 and big + F(1, 2) < F(2) ** 100, "sin_shifter")
    radius = F(1, 128)
    for index in range(16, 65):
        x = Ball([0, 1], minnormal(53), radius)
        z = x.mul(x)
        sn5, sn3, cs6, cs4, cs2 = [coefficients(sine, offset, 1)[0] for offset in (0x9f000, 0x9f008, 0x9f010, 0x9f018, 0x9cbd0)]
        h = z.fma(constant(sn5, radius), constant(sn3, radius))
        s = x.mul(z).fma(h, constant(0, radius)).fma(constant(1, radius), x)
        h = z.fma(constant(cs6, radius), constant(cs4, radius))
        h = z.fma(h, constant(cs2, radius))
        c = x.fma(constant(0, radius), z.mul(h))
        sn, ssn, cs, ccs = coefficients(sine, 0xd2be0 + (index - 16) * 32, 4)
        cor = s.fma(constant(ccs, radius), constant(ssn, radius))
        cor = Ball([-v for v in c.p], c.e, radius).fma(constant(sn, radius), cor)
        cor = s.fma(constant(cs, radius), cor)
        y = cor.fma(constant(1, radius), constant(sn, radius))
        angle = F(index, 128)
        sa = sum(F((-1) ** k, factorial(2 * k + 1)) * angle ** (2 * k + 1) for k in range(13))
        ca = sum(F((-1) ** k, factorial(2 * k)) * angle ** (2 * k) for k in range(13))
        ideal = [F(0)] * 7
        for k in range(4):
            ideal[2 * k] += sa * F((-1) ** k, factorial(2 * k))
        for k in range(3):
            ideal[2 * k + 1] += ca * F((-1) ** k, factorial(2 * k + 1))
        approx = Ball(add_poly(y.p, [-v for v in ideal]), radius=radius).norm()
        tail = angle ** 27 / factorial(27) + angle ** 26 / factorial(26)
        tail += abs(sa) * radius ** 8 / factorial(8) + abs(ca) * radius ** 7 / factorial(7)
        bound = up(y.e + approx + tail)
        require(angle - radius - (angle + radius) ** 3 / 6 > bound, "sin_sign_restore")
        bounds.append(bound)

    radius = F(1, 2)
    cs = [coefficients(profiles["sinf"], offset, 1)[0] for offset in (0xd4c00, 0xd4bf0, 0xd4be0)]
    x = Ball([0, 1], minnormal(24))
    z = x.mul(x)
    x3 = x.mul(z)
    h = z.fma(constant(cs[0]), constant(cs[1]))
    y = h.fma(x3.mul(z), x3.fma(constant(cs[2]), x)).convert(24)
    ideal = [F(0)] * 8
    for k in range(4):
        ideal[2 * k + 1] = F((-1) ** k, factorial(2 * k + 1))
    approx = Ball(add_poly(y.p, [-v for v in ideal])).norm()
    bound = up(y.e + approx + radius ** 9 / factorial(9))
    tiny = up(F(2) ** -36 / 6 + minnormal(24))
    return {"sin": max(bounds), "sinf": max(bound, tiny)}


def linux_acos_bound(profile):
    require(read_memory(profile, 0x9c7b0, 8) == bytes(8), "acos_positive_addend")
    radius = F(1, 10)
    t = Ball([0, 1], radius=radius)
    cs = [coefficients(profile, 0xd3de0 + 8 * i, 1)[0] for i in range(12)]
    pairs = [t.fma(constant(cs[i + 1], radius), constant(cs[i], radius)) for i in range(0, 12, 2)]
    t2 = t.mul(t)
    t4 = t2.mul(t2)
    a = t2.fma(pairs[1], pairs[0])
    b = t2.fma(pairs[3], pairs[2])
    c = t2.fma(pairs[5], pairs[4])
    h = t4.fma(t4.fma(c, b), a)
    require(len(h.p) == 12, "acosf_polynomial_degree")
    error, output_max = positive_acos_bound(h)
    require(output_max < F(12, 25), "acosf_output_range")
    return error


def validate_linux_control(profiles):
    # Independent PC arithmetic binds each equation's constants to actual operands.
    references = {
        "sin": [(0x6dc5c, 4, 8, 0x938f0), (0x6dca5, 4, 8, 0x9efd0),
                (0x6dcdd, 4, 8, 0x9eff8), (0x6dccb, 3, 7, 0xd29e0),
                (0x6dcc3, 4, 8, 0x9f000), (0x6dd17, 5, 9, 0x9f008),
                (0x6dd29, 4, 8, 0x9f010), (0x6dd31, 5, 9, 0x9f018),
                (0x6dd3a, 5, 9, 0x9cbd0), (0x6e014, 4, 8, 0x9efd8),
                (0x6e020, 5, 9, 0x9efe0), (0x6e029, 5, 9, 0x9efe8),
                (0x6e032, 5, 9, 0x9eff0), (0x6e03b, 5, 9, 0x9ed20),
                (0x6e044, 5, 9, 0x938e0)],
        "sinf": [(0x806a0, 4, 8, 0xd4c00), (0x806a8, 5, 9, 0xd4bf0),
                 (0x806b5, 5, 9, 0xd4be0)],
        "acosf": [(0x17ff4, 4, 8, 0x93900), (0x17ffc, 4, 8, 0x93000),
                  (0x78358, 4, 8, 0x938f0), (0x78360, 4, 8, 0x9cbd8),
                  (0x78368, 4, 8, 0x938e0), (0x78383, 3, 7, 0x9c7b0),
                  (0x78373, 4, 8, 0xd3de8), (0x7837b, 4, 8, 0xd3df8),
                  (0x7838e, 4, 8, 0xd3e08), (0x78396, 5, 9, 0xd3de0),
                  (0x7839f, 4, 8, 0xd3e18), (0x783a7, 4, 8, 0xd3e28),
                  (0x783af, 5, 9, 0xd3df0), (0x783b8, 4, 8, 0xd3e30),
                  (0x783c0, 5, 9, 0xd3e00), (0x783cd, 5, 9, 0xd3e10),
                  (0x783d6, 5, 9, 0xd3e20), (0x783ef, 5, 9, 0xd3e38)]}
    for name, refs in references.items():
        for pc, displacement, size, target in refs:
            require(rip_target(profiles[name], pc, displacement, size) == target, "operand_reference_" + name)
    sine, cosine = profiles["sin"], profiles["acosf"]
    require(F(1, 8) < coefficients(sine, 0x9efd0, 1)[0] < F(13, 100), "sin_branch_cut")
    require(read_memory(sine, 0x938f0, 8) == bytes.fromhex("ffffffffffffff7f"), "abs64_mask")
    require(read_memory(sine, 0x938e0, 8) == bytes.fromhex("0000000000000080"), "sign64_mask")
    require(rip_target(sine, 0x6dc4f, 2, 6) == 0x6e060, "sin_rounding_entry")
    require(rip_target(sine, 0x6e0c5, 1, 5) == 0x6dc92, "sin_rounding_classifier")
    require(read_memory(sine, 0x6e0c0, 5) == bytes.fromhex("b901000000"), "sin_rounding_restore_flag")
    require(read_memory(profiles["sinf"], 0x8086d, 5) == bytes.fromhex("c5f35ac9c3"), "sinf_tiny_return")
    require(read_memory(cosine, 0x93900, 4) == bytes.fromhex("ffffff7f"), "abs32_mask")
    require(read_memory(cosine, 0x93000, 4) == bytes.fromhex("0000803f"), "acos_wrapper_cut")
    require(coefficients(cosine, 0x9cbd8, 1)[0] == 1, "acos_exact_subtraction")
    require(rip_target(cosine, 0x18006, 1, 5) == 0x78180, "acos_actual_wrapper_target")
    require(rip_target(cosine, 0x78190, 2, 6) == 0x78438, "acos_endpoint_classifier")
    require(rip_target(cosine, 0x78438, 1, 5) == 0x78130, "acos_endpoint_helper")
    require(rip_target(cosine, 0x78139, 1, 2, 1) == 0x78160, "acos_endpoint_branch")
    require(read_memory(cosine, 0x78160, 5) == bytes.fromhex("c5f857c0c3"), "acos_endpoint_zero")
    require(F(12, 25) * F(513, 512) < F(1, 2), "sine_argument_range")


def prove(capture):
    require(isinstance(capture, dict), "capture_object")
    require(isinstance(capture.get("native", {}), dict), "native_object")
    platform = capture.get("native", {}).get("platform")
    require(platform in ("macos-arm64", "linux-x86_64"), "unknown_profile")
    linux = platform == "linux-x86_64"
    profile_id = LINUX_ID if linux else MAC_ID
    expected_profiles = LINUX_PROFILE if linux else MAC_PROFILE
    image_path = "/usr/lib/x86_64-linux-gnu/libm.so.6" if linux else "/usr/lib/system/libsystem_m.dylib"
    require(capture.get("schema") == SCHEMA, "capture_schema")
    require(all(isinstance(capture.get(key), dict) for key in ("engine", "acquisition")), "identity_envelope_object")
    native, engine, acquisition = capture["native"], capture["engine"], capture["acquisition"]
    require(type(native.get("schema")) is int and native["schema"] == 1, "native_schema")
    require(type(native.get("pid")) is int and native["pid"] > 0 and type(engine.get("pid")) is int and native["pid"] == engine["pid"], "process_identity")
    require(isinstance(native.get("engine_path"), str) and bool(native["engine_path"]), "engine_path_present")
    require(native.get("engine_path") == engine.get("executable"), "engine_path_identity")
    require(engine.get("architecture") == ("x86_64" if linux else "arm64"), "engine_architecture")
    require(isinstance(engine.get("version"), dict), "engine_version_object")
    require(all(type(engine["version"].get(key)) is int and engine["version"][key] >= 0 for key in ("major", "minor", "patch")), "engine_version_components")
    require(native.get("engine_version_components") == [engine.get("version", {}).get(key) for key in ("major", "minor", "patch")], "engine_version_identity")
    require(isinstance(native.get("engine_image_id"), str) and native["engine_image_id"] == acquisition.get("engine_image_id"), "engine_image_identity")
    image_ids = acquisition.get("selected_binary_image_ids", [])
    require(isinstance(image_ids, list), "selected_engine_image_ids")
    require(native.get("engine_image_id") in image_ids if native.get("engine_image_id") else linux and image_ids == [], "selected_engine_image_identity")
    require(engine.get("executable_sha256") == acquisition.get("engine_sha256"), "engine_hash_identity")
    require(native.get("selected_engine_sha256") == acquisition.get("engine_sha256"), "native_engine_hash_identity")
    require(native.get("header_sha256") == acquisition.get("header_sha256"), "abi_header_identity")
    require(engine.get("collector_sha256") == acquisition.get("collector_sha256"), "collector_binary_identity")
    for field in ("header_sha256", "collector_sha256", "source_sha256", "script_sha256", "engine_sha256"):
        value = acquisition.get(field)
        require(isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value), "missing_acquisition_" + field)
    require(acquisition["source_sha256"] == file_hash(ROOT / "capture.c"), "collector_source_identity")
    require(acquisition["script_sha256"] == file_hash(ROOT / "capture.gd"), "script_identity")
    require(isinstance(native.get("imports"), list) and len(native["imports"]) == 3, "missing_imports")
    profiles = {}
    for name, slots in zip(("sin", "sinf", "acosf"), native["imports"]):
        require(isinstance(slots, list) and len(slots) >= 1, "missing_import_" + name)
        for record in slots:
            require(isinstance(record, dict), "import_record_" + name)
            require(record.get("symbol") == name, "import_symbol_" + name)
            require(record.get("image_id") == profile_id, "unknown_profile_" + name)
            require(record.get("image_path") == image_path, "import_image_" + name)
            require(record.get("dlsym_equal") is (not (linux and name == "acosf")), "unresolved_import_" + name)
            require(int(record["target"], 16) - int(record["image_base"], 16) == record.get("entry_offset"), "import_address_" + name)
            expected = expected_profiles[name]
            for field in expected:
                require(record.get(field) == expected[field], "instruction_or_constant_mismatch_" + name + "_" + field)
            profiles[name] = record
    if linux:
        validate_linux_control(profiles)
        bounds = linux_sine_bounds(profiles)
        bounds["acosf"] = linux_acos_bound(profiles["acosf"])
    else:
        bounds = mac_bounds(profiles)
    claimed = {"sin": F(2) ** -48, "sinf": F(2) ** -22, "acosf": F(2) ** -22}
    require(all(0 < bounds[name] <= claimed[name] for name in bounds), "derived_error_exceeds_claim")
    theorem = {name: {"domain": ["9/10", "1"] if name == "acosf" else ["-1/2", "1/2"],
                      "input_format": "binary64" if name == "sin" else "binary32",
                      "derived_absolute_error": str(bound), "outward_absolute_error": str(claimed[name])}
               for name, bound in bounds.items()}
    receipt = {"schema": SCHEMA, "status": "closed_scalar_value_proof", "profile": platform + "/" + profile_id,
               "capture_sha256": digest(canonical(capture)), "verifier_sha256": file_hash(__file__),
               "theorems": theorem, "engine_sha256": acquisition["engine_sha256"],
               "scope": "scalar values only; no derivative, source-domain, JETS or physical E acceptance",
               "assumptions": "IEEE binary32/binary64 basic operations/FMA/sqrt; all rounding directions; explicit FTZ allowances; intermediates below 2^100"}
    receipt["sha256"] = digest(canonical(receipt))
    return receipt


def verify_receipt(receipt, capture):
    require(receipt == prove(capture), "receipt_mismatch")


def run(command, directory, env=None):
    result = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True, timeout=60)
    require(result.returncode == 0, "command_failed: " + repr(command) + "\n" + result.stdout + result.stderr)
    require("SCRIPT ERROR:" not in result.stdout + result.stderr, "godot_script_error: " + result.stdout + result.stderr)
    return result.stdout


def require_ignored(path):
    result = subprocess.run(["git", "check-ignore", "--quiet", str(path.resolve())],
                            cwd=ROOT.parents[2], capture_output=True, timeout=60)
    require(result.returncode == 0, "output_not_ignored: " + str(path))


def acquire(engine, scratch):
    engine = str(Path(engine).resolve(strict=True))
    engine_hash = file_hash(engine)
    engine_ids = binary_image_ids(engine)
    scratch = scratch.resolve()
    require_ignored(scratch)
    scratch.mkdir(parents=True, exist_ok=False)
    (scratch / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Native arithmetic diagnostic"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
    shutil.copyfile(ROOT / "capture.gd", scratch / "capture.gd")
    run([engine, "--headless", "--path", str(scratch), "--dump-gdextension-interface"], scratch)
    header = scratch / "gdextension_interface.h"
    require(header.is_file(), "missing_selected_engine_abi_header")
    compiler = shutil.which("cc")
    require(compiler is not None, "missing_existing_system_c_compiler")
    library = scratch / ("capture.dylib" if sys.platform == "darwin" else "capture.so")
    header_hash = file_hash(header)
    command = [compiler, "-std=c11", "-Wall", "-Wextra", "-Werror", "-fPIC", "-I", str(scratch),
               '-DROYAL_NATIVE_HEADER_SHA256="' + header_hash + '"',
               '-DROYAL_NATIVE_ENGINE_SHA256="' + engine_hash + '"', str(ROOT / "capture.c")]
    command += ["-dynamiclib"] if sys.platform == "darwin" else ["-shared", "-ldl"]
    run(command + ["-o", str(library)], scratch)
    descriptor = scratch / "capture.gdextension"
    descriptor.write_text('[configuration]\nentry_symbol="royal_native_arithmetic_init"\ncompatibility_minimum="4.7"\n[libraries]\n' + ('macos.arm64' if sys.platform == "darwin" else 'linux.x86_64') + '="' + str(library) + '"\n')
    native_path = scratch / "native.json"
    env = dict(os.environ, ROYAL_NATIVE_CAPTURE=str(native_path), ROYAL_NATIVE_EXTENSION=str(descriptor), ROYAL_NATIVE_LIBRARY=str(library))
    log = run([engine, "--headless", "--path", str(scratch), "--script", "res://capture.gd"], scratch, env)
    (scratch / "capture.log").write_text(log)
    require(file_hash(engine) == engine_hash, "engine_changed_during_capture")
    native = json.loads(native_path.read_text())
    require(native.get("engine_image_id") in engine_ids if engine_ids else native.get("engine_image_id") == "", "loaded_engine_not_selected_binary")
    capture = {"schema": SCHEMA, "native": native,
               "engine": json.loads(Path(str(native_path) + ".engine.json").read_text()),
               "acquisition": {"engine_sha256": engine_hash,
                   "engine_image_id": native["engine_image_id"],
                   "selected_binary_image_ids": engine_ids,
                   "header_sha256": file_hash(header), "collector_sha256": file_hash(library),
                   "source_sha256": file_hash(ROOT / "capture.c"), "script_sha256": file_hash(ROOT / "capture.gd")}}
    (scratch / "capture.json").write_text(json.dumps(capture, indent=2) + "\n")
    return capture


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--verify", type=Path)
    mode.add_argument("--capture", metavar="GODOT")
    parser.add_argument("--scratch", type=Path)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args()
    capture = None
    try:
        require(not args.receipt.exists(), "receipt_already_exists")
        if args.capture:
            require(args.scratch is not None, "explicit_ignored_scratch_required")
            capture = acquire(args.capture, args.scratch)
        else:
            capture = json.loads(args.verify.read_text())
        receipt = prove(capture)
        require_ignored(args.receipt)
        with args.receipt.open("x") as stream:
            stream.write(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps(receipt, sort_keys=True))
        return 0
    except (Rejected, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print(json.dumps({"status": "rejected", "witness": str(error), "capture": capture}, sort_keys=True))
        return 1


if __name__ == "__main__":
    sys.exit(main())
