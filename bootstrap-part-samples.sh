# shellcheck shell=bash
# Part: adoption changes for the averittintdev LTL sample repos. Sourced by bootstrap-ci-templates.sh.
#
# test-fixtures/samples/<stack>/ is overlaid onto a fresh checkout of the real sample repo by
# self-test.yml (jobs sample-node / sample-java), which must then pass every module. The same
# files are the pull request to raise in each sample repo; once merged, the overlay can go.

w test-fixtures/samples/README.md <<'__FILE__'
# LTL sample adoption changes

`self-test.yml` checks out the real sample repos, copies these files over them and runs every
module, which must pass. They are the minimum changes each sample needs to meet the CI standard,
so they double as the pull request to raise in that repo.

| Sample | Why it fails as-is | Change |
|---|---|---|
| `ltl-tracking-api-client-sample-nodejs` | `npm test` is the placeholder that exits 1; ESLint `no-unused-vars` (`res`); `npm audit` high (Express 4.18.1: body-parser, path-to-regexp); `index.js` reads `/home/jason/...` and listens at require time, so nothing is testable | `index.js` exports `createApp`/`verifySignature`/`extractSignature`/`loadPublicKey`, only starts the server when run directly, reads the key from `PUBLIC_KEY_PATH` (old path stays the default), answers `201` like the Java sample and no longer crashes without an `Authorization` header; `node:test` suite; Express `^4.21.2`; `.nvmrc` |
| `ltl-tracking-api-client-sample-java` | `contextLoads` fails: `${public.key}` is not defined anywhere; SpotBugs `DM_DEFAULT_ENCODING` (High) on `getBytes()` | Test supplies a generated RSA key via `@DynamicPropertySource`; `MainController` uses UTF-8 explicitly, tolerates a missing `Authorization` header and is `final`; unit tests for signature verification; `lombok.config` marks Lombok code `@Generated` so JaCoCo/SpotBugs ignore it |

For the Node.js PR, also run `npm install` after applying `package.json` and commit the updated
`package-lock.json` (the self-test does the same with `npm install --package-lock-only`).
__FILE__

# ---------------------------------------------------------------- Node.js sample
w test-fixtures/samples/node/.nvmrc <<'__FILE__'
22
__FILE__

w test-fixtures/samples/node/package.json <<'__FILE__'
{
  "name": "nodejs-server",
  "version": "1.0.0",
  "description": "Test server that receives JSON requests",
  "main": "index.js",
  "files": [
    "index.js"
  ],
  "scripts": {
    "pretest": "node -e \"const fs=require('fs');fs.mkdirSync('reports/junit',{recursive:true});fs.mkdirSync('coverage',{recursive:true})\"",
    "test": "node --test --experimental-test-coverage --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=reports/junit/node-test.xml --test-reporter=lcov --test-reporter-destination=coverage/lcov.info",
    "start": "node index.js"
  },
  "author": "Jason Long",
  "license": "ISC",
  "dependencies": {
    "express": "^4.21.2"
  }
}
__FILE__

w test-fixtures/samples/node/index.js <<'__FILE__'
"use strict";

const express = require("express");
const crypto = require("crypto");
const fs = require("fs");

const DEFAULT_PUBLIC_KEY_PATH = "/home/jason/software/temp/public_key_rsa_4096_pkcs8-exported.pem";
const PORT = 8888;

function loadPublicKey(keyPath) {
  const publicKeyStr = fs.readFileSync(keyPath);
  return crypto.createPublicKey({ key: publicKeyStr, format: "pem", type: "spki" });
}

function extractSignature(authorizationHdr) {
  const matched = /signature="(.*)"/.exec(authorizationHdr || "");
  return matched ? matched[1] : null;
}

function verifySignature(publicKey, signature, inputData) {
  return crypto.verify(
    "rsa-sha256",
    Buffer.from(inputData, "utf8"),
    publicKey,
    Buffer.from(signature, "base64")
  );
}

function createApp(publicKey) {
  const app = express();
  app.use(express.urlencoded({ extended: true }));
  app.use(express.json());

  app.post("/shipments", (req, res) => {
    console.log(req.body);
    const inputStr = `${req.header("host")}${req.header("date")}${req.header("digest")}`;
    const signature = extractSignature(req.header("authorization"));
    const isVerified = signature !== null && verifySignature(publicKey, signature, inputStr);
    console.log("inputStr : %s | signature : %s | isVerified : %s", inputStr, signature, isVerified);
    res.sendStatus(201);
  });

  return app;
}

if (require.main === module) {
  const publicKey = loadPublicKey(process.env.PUBLIC_KEY_PATH || DEFAULT_PUBLIC_KEY_PATH);
  const server = createApp(publicKey).listen(PORT, () => {
    console.log("listening at %o", server.address());
  });
}

module.exports = { createApp, extractSignature, verifySignature, loadPublicKey };
__FILE__

w test-fixtures/samples/node/test/index.test.js <<'__FILE__'
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { once } = require("node:events");
const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { createApp, extractSignature, verifySignature, loadPublicKey } = require("../index");

const { publicKey, privateKey } = crypto.generateKeyPairSync("rsa", { modulusLength: 2048 });

function sign(data) {
  return crypto.sign("rsa-sha256", Buffer.from(data, "utf8"), privateKey).toString("base64");
}

async function startServer(t) {
  const server = createApp(publicKey).listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  return server.address().port;
}

function postShipment(port, headers) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        host: "127.0.0.1",
        port,
        path: "/shipments",
        method: "POST",
        headers: { "content-type": "application/json", ...headers },
      },
      (res) => {
        res.resume();
        res.on("end", () => resolve(res.statusCode));
      }
    );
    req.on("error", reject);
    req.end(JSON.stringify({ proNumber: "123456789" }));
  });
}

test("extractSignature returns the signature parameter", () => {
  assert.equal(extractSignature('Signature keyId="test",signature="abc=="'), "abc==");
});

test("extractSignature returns null when there is no signature", () => {
  assert.equal(extractSignature(undefined), null);
  assert.equal(extractSignature("Bearer token"), null);
});

test("verifySignature accepts a valid signature and rejects a tampered payload", () => {
  const signature = sign("host-date-digest");
  assert.equal(verifySignature(publicKey, signature, "host-date-digest"), true);
  assert.equal(verifySignature(publicKey, signature, "host-date-digest-tampered"), false);
});

test("loadPublicKey reads an SPKI PEM file", (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "ltl-sample-"));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const file = path.join(dir, "public.pem");
  fs.writeFileSync(file, publicKey.export({ type: "spki", format: "pem" }));
  assert.equal(loadPublicKey(file).asymmetricKeyType, "rsa");
});

test("POST /shipments acknowledges a signed callback with 201", async (t) => {
  const port = await startServer(t);
  const date = new Date().toUTCString();
  const digest = "SHA-256=abc";
  const signature = sign(`127.0.0.1:${port}${date}${digest}`);
  const status = await postShipment(port, {
    date,
    digest,
    authorization: `Signature keyId="test",signature="${signature}"`,
  });
  assert.equal(status, 201);
});

test("POST /shipments without an Authorization header does not crash", async (t) => {
  const port = await startServer(t);
  assert.equal(await postShipment(port, {}), 201);
});
__FILE__

# ---------------------------------------------------------------- Java sample
w test-fixtures/samples/java/lombok.config <<'__FILE__'
config.stopBubbling = true
lombok.addLombokGeneratedAnnotation = true
__FILE__

w test-fixtures/samples/java/src/main/java/com/averitt/clientsamples/MainController.java <<'__FILE__'
package com.averitt.clientsamples;

import com.averitt.clientsamples.entity.ProDetails;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.security.InvalidKeyException;
import java.security.KeyFactory;
import java.security.NoSuchAlgorithmException;
import java.security.PublicKey;
import java.security.Signature;
import java.security.SignatureException;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Slf4j
@RestController
public final class MainController
{
    private static final String SIGNING_ALGORITHM = "SHA256withRSA";
    private final PublicKey publicKey;

    public MainController(@Value("${public.key}") String publicKeyStr)
        throws NoSuchAlgorithmException,
               InvalidKeySpecException
    {
        byte[] publicBytes = Base64.getDecoder().decode(publicKeyStr);
        X509EncodedKeySpec keySpec = new X509EncodedKeySpec(publicBytes);
        KeyFactory keyFactory = KeyFactory.getInstance("RSA");
        this.publicKey = keyFactory.generatePublic(keySpec);
    }

    @PostMapping("/shipments")
    public ResponseEntity<Void> updateShipment(@RequestHeader Map<String, String> headers,
                                               @RequestBody ProDetails proDetails)
    {
        log.info("Update Shipment ... proDetails : " + proDetails);

        headers.forEach((key, value) -> log.info(String.format("Header '%s' = %s", key, value)));

        String signature = "";

        String authorization = headers.getOrDefault("authorization", "");

        Pattern signaturePattern = Pattern.compile(".signature=\"(.*)\"");
        Matcher signatureMatcher = signaturePattern.matcher(authorization);
        if (signatureMatcher.find()) {
            signature = signatureMatcher.group(1);
        }

        String digest = headers.get("digest");
        String date = headers.get("date");
        String host = headers.get("host");

        String inputStr = host + date + digest;
        log.info("inputStr : " + inputStr);
        log.info("signature : " + signature);

        byte[] input = inputStr.getBytes(StandardCharsets.UTF_8);
        boolean isLegit = false;

        try {
            isLegit = isLegitDigitalSignature(input, Base64.getDecoder().decode(signature), publicKey);
        } catch (NoSuchAlgorithmException | InvalidKeyException | SignatureException ex) {
            log.error("", ex);
        }

        log.info("isLegit : " + isLegit);

        return new ResponseEntity<>(HttpStatus.CREATED);
    }

    public static boolean isLegitDigitalSignature(byte[] input, byte[] signatureToVerify, PublicKey publicKey)
            throws NoSuchAlgorithmException,
                   InvalidKeyException,
                   SignatureException
    {
        Signature signature = Signature.getInstance(SIGNING_ALGORITHM);
        signature.initVerify(publicKey);
        signature.update(input);
        return signature.verify(signatureToVerify);
    }
}
__FILE__

w test-fixtures/samples/java/src/test/java/com/averitt/clientsamples/TestKeys.java <<'__FILE__'
package com.averitt.clientsamples;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.util.Base64;

/** Throwaway RSA keys so tests never depend on a developer-local key file. */
final class TestKeys {

    private TestKeys() {
    }

    static KeyPair rsaKeyPair() {
        try {
            KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
            generator.initialize(2048);
            return generator.generateKeyPair();
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("RSA is not available", ex);
        }
    }

    static String encodedPublicKey(KeyPair keys) {
        return Base64.getEncoder().encodeToString(keys.getPublic().getEncoded());
    }
}
__FILE__

w test-fixtures/samples/java/src/test/java/com/averitt/clientsamples/ClientSamplesApplicationTests.java <<'__FILE__'
package com.averitt.clientsamples;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;

@SpringBootTest
class ClientSamplesApplicationTests {

    @DynamicPropertySource
    static void publicKey(DynamicPropertyRegistry registry) {
        String encoded = TestKeys.encodedPublicKey(TestKeys.rsaKeyPair());
        registry.add("public.key", () -> encoded);
    }

    @Test
    void contextLoads() {
    }

}
__FILE__

w test-fixtures/samples/java/src/test/java/com/averitt/clientsamples/MainControllerTest.java <<'__FILE__'
package com.averitt.clientsamples;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.averitt.clientsamples.entity.ProDetails;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.Signature;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

class MainControllerTest {

    private static final KeyPair KEYS = TestKeys.rsaKeyPair();
    private static final String HOST = "localhost:8888";
    private static final String DATE = "Mon, 23 Nov 2026 16:00:00 GMT";
    private static final String DIGEST = "SHA-256=abc";

    private static byte[] sign(String data) throws GeneralSecurityException {
        Signature signer = Signature.getInstance("SHA256withRSA");
        signer.initSign(KEYS.getPrivate());
        signer.update(data.getBytes(StandardCharsets.UTF_8));
        return signer.sign();
    }

    @Test
    void acceptsAValidSignature() throws GeneralSecurityException {
        byte[] input = (HOST + DATE + DIGEST).getBytes(StandardCharsets.UTF_8);
        assertTrue(MainController.isLegitDigitalSignature(input, sign(HOST + DATE + DIGEST), KEYS.getPublic()));
    }

    @Test
    void rejectsATamperedPayload() throws GeneralSecurityException {
        byte[] tampered = (HOST + DATE + "SHA-256=tampered").getBytes(StandardCharsets.UTF_8);
        assertFalse(MainController.isLegitDigitalSignature(tampered, sign(HOST + DATE + DIGEST), KEYS.getPublic()));
    }

    @Test
    void updateShipmentAcknowledgesWithCreated() throws GeneralSecurityException {
        MainController controller = new MainController(TestKeys.encodedPublicKey(KEYS));
        Map<String, String> headers = new HashMap<>();
        headers.put("host", HOST);
        headers.put("date", DATE);
        headers.put("digest", DIGEST);
        String signature = Base64.getEncoder().encodeToString(sign(HOST + DATE + DIGEST));
        headers.put("authorization", "Signature keyId=\"test\",signature=\"" + signature + "\"");

        ResponseEntity<Void> response = controller.updateShipment(headers, new ProDetails());

        assertEquals(HttpStatus.CREATED, response.getStatusCode());
    }

    @Test
    void updateShipmentToleratesAMissingAuthorizationHeader() throws GeneralSecurityException {
        MainController controller = new MainController(TestKeys.encodedPublicKey(KEYS));

        ResponseEntity<Void> response = controller.updateShipment(new HashMap<>(), new ProDetails());

        assertEquals(HttpStatus.CREATED, response.getStatusCode());
    }
}
__FILE__
