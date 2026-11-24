# shellcheck shell=bash
# Part: self-test fixtures (pass + deliberately broken) per stack. Sourced by bootstrap-ci-templates.sh.

# ---------------------------------------------------------------- Node.js
node_fixture() { # <dir> <math.js body>
  w "$1/.nvmrc" <<'__FILE__'
22
__FILE__
  w "$1/package.json" <<'__FILE__'
{
  "name": "@averitt/ci-templates-fixture-node",
  "version": "1.0.0",
  "description": "ci-templates self-test fixture",
  "private": true,
  "license": "UNLICENSED",
  "main": "src/math.js",
  "files": ["src/"],
  "scripts": {
    "pretest": "node -e \"const fs=require('fs');fs.mkdirSync('reports/junit',{recursive:true});fs.mkdirSync('coverage',{recursive:true})\"",
    "test": "node --test --experimental-test-coverage --test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=reports/junit/node-test.xml --test-reporter=lcov --test-reporter-destination=coverage/lcov.info"
  }
}
__FILE__
  w "$1/package-lock.json" <<'__FILE__'
{
  "name": "@averitt/ci-templates-fixture-node",
  "version": "1.0.0",
  "lockfileVersion": 3,
  "requires": true,
  "packages": {
    "": {
      "name": "@averitt/ci-templates-fixture-node",
      "version": "1.0.0",
      "license": "UNLICENSED"
    }
  }
}
__FILE__
  w "$1/src/math.js" <<<"$2"
  w "$1/test/math.test.js" <<'__FILE__'
"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { add, divide } = require("../src/math");

test("add sums two numbers", () => {
  assert.equal(add(2, 3), 5);
});

test("divide divides two numbers", () => {
  assert.equal(divide(10, 4), 2.5);
});

test("divide rejects division by zero", () => {
  assert.throws(() => divide(1, 0), /division by zero/);
});
__FILE__
}

node_fixture test-fixtures/node/pass '"use strict";

function add(a, b) {
  return a + b;
}

function divide(a, b) {
  if (b === 0) {
    throw new RangeError("division by zero");
  }
  return a / b;
}

module.exports = { add, divide };'

# Broken: unused variable (ESLint no-unused-vars error) and a wrong add (failing test).
node_fixture test-fixtures/node/broken '"use strict";

const unusedSetting = 42;

function add(a, b) {
  return a - b;
}

function divide(a, b) {
  if (b === 0) {
    throw new RangeError("division by zero");
  }
  return a / b;
}

module.exports = { add, divide };'

# ---------------------------------------------------------------- Java
java_fixture() { # <dir> <Calculator.java body>
  w "$1/pom.xml" <<'__FILE__'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.averitt.citemplates</groupId>
  <artifactId>ci-templates-fixture-java</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <packaging>jar</packaging>

  <properties>
    <maven.compiler.release>17</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>

  <dependencies>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.10.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-compiler-plugin</artifactId>
        <version>3.13.0</version>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.2.5</version>
      </plugin>
    </plugins>
  </build>
</project>
__FILE__
  w "$1/src/main/java/com/averitt/citemplates/Calculator.java" <<<"$2"
  w "$1/src/test/java/com/averitt/citemplates/CalculatorTest.java" <<'__FILE__'
package com.averitt.citemplates;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import org.junit.jupiter.api.Test;

class CalculatorTest {

    @Test
    void addSumsTwoNumbers() {
        assertEquals(5, Calculator.add(2, 3));
    }

    @Test
    void divideDividesTwoNumbers() {
        assertEquals(2, Calculator.divide(10, 5));
    }

    @Test
    void divideRejectsDivisionByZero() {
        assertThrows(ArithmeticException.class, () -> Calculator.divide(1, 0));
    }
}
__FILE__
}

java_fixture test-fixtures/java/pass 'package com.averitt.citemplates;

public final class Calculator {

    private Calculator() {
    }

    public static int add(int a, int b) {
        return a + b;
    }

    public static int divide(int a, int b) {
        if (b == 0) {
            throw new ArithmeticException("division by zero");
        }
        return a / b;
    }
}'

# Broken: unused import (Checkstyle UnusedImports error) and a wrong add (failing test).
java_fixture test-fixtures/java/broken 'package com.averitt.citemplates;

import java.util.List;

public final class Calculator {

    private Calculator() {
    }

    public static int add(int a, int b) {
        return a - b;
    }

    public static int divide(int a, int b) {
        if (b == 0) {
            throw new ArithmeticException("division by zero");
        }
        return a / b;
    }
}'

# ---------------------------------------------------------------- PHP
php_fixture() { # <dir> <Calculator.php body>
  w "$1/phpunit.xml.dist" <<'__FILE__'
<?xml version="1.0" encoding="UTF-8"?>
<phpunit bootstrap="src/Calculator.php" colors="true" failOnWarning="true">
  <testsuites>
    <testsuite name="unit">
      <directory>tests</directory>
    </testsuite>
  </testsuites>
  <source>
    <include>
      <directory>src</directory>
    </include>
  </source>
</phpunit>
__FILE__
  w "$1/src/Calculator.php" <<<"$2"
  w "$1/tests/CalculatorTest.php" <<'__FILE__'
<?php

declare(strict_types=1);

namespace Averitt\CiTemplates\Tests;

use Averitt\CiTemplates\Calculator;
use PHPUnit\Framework\TestCase;

final class CalculatorTest extends TestCase
{
    public function testAddSumsTwoNumbers(): void
    {
        self::assertSame(5, (new Calculator())->add(2, 3));
    }

    public function testDivideDividesTwoNumbers(): void
    {
        self::assertSame(2.5, (new Calculator())->divide(10, 4));
    }

    public function testDivideRejectsDivisionByZero(): void
    {
        $this->expectException(\DivisionByZeroError::class);
        (new Calculator())->divide(1, 0);
    }
}
__FILE__
}

php_fixture test-fixtures/php/pass '<?php

declare(strict_types=1);

namespace Averitt\CiTemplates;

final class Calculator
{
    public function add(int $a, int $b): int
    {
        return $a + $b;
    }

    public function divide(int $a, int $b): float
    {
        if ($b === 0) {
            throw new \DivisionByZeroError("division by zero");
        }
        return $a / $b;
    }
}'

# Broken: class brace on the same line (PSR-12 error) and a wrong add (failing test).
php_fixture test-fixtures/php/broken '<?php

declare(strict_types=1);

namespace Averitt\CiTemplates;

final class Calculator {
    public function add(int $a, int $b): int
    {
        return $a - $b;
    }

    public function divide(int $a, int $b): float
    {
        if ($b === 0) {
            throw new \DivisionByZeroError("division by zero");
        }
        return $a / $b;
    }
}'

w test-fixtures/README.md <<'__FILE__'
# Self-test fixtures

Used by `.github/workflows/self-test.yml` and `release-smoke.yml`. Do not use them as project templates.

| Fixture | Expectation |
|---|---|
| `<stack>/pass` | lint, test, quality (coverage >= 80%) and package all succeed |
| `<stack>/broken` | lint fails (Node: unused variable; Java: unused import; PHP: PSR-12 brace) **and** tests fail (wrong `add`) |
__FILE__
