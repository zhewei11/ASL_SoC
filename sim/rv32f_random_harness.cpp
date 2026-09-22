#include "Vrv32f_unit.h"
#include "verilated.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <random>

static uint32_t float_bits(float value)
{
    uint32_t bits;
    std::memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float bits_float(uint32_t bits)
{
    float value;
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

static uint32_t canonicalize_nan(float value)
{
    return std::isnan(value) ? 0x7fc00000u : float_bits(value);
}

static void tick(Vrv32f_unit &dut)
{
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
}

static uint32_t execute(Vrv32f_unit &dut, uint32_t instruction,
                        uint32_t a, uint32_t b, uint32_t c)
{
    dut.instruction = instruction;
    dut.operand_a = a;
    dut.operand_b = b;
    dut.operand_c = c;
    dut.dynamic_rounding_mode = 0;
    dut.start = 1;
    tick(dut);
    dut.start = 0;

    for (unsigned latency = 0; latency <= 20; ++latency) {
        if (dut.valid) {
            uint32_t result = dut.result;
            tick(dut);
            if (dut.valid) {
                std::cerr << "FPU response valid exceeded one cycle\n";
                std::exit(2);
            }
            return result;
        }
        tick(dut);
    }

    std::cerr << "FPU response timed out\n";
    std::exit(2);
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Vrv32f_unit dut;
    dut.rst = 1;
    dut.flush = 0;
    dut.start = 0;
    dut.clk = 0;
    dut.eval();
    dut.clk = 1;
    dut.eval();
    dut.rst = 0;

    constexpr uint32_t op_fp = 0x53u;
    constexpr uint32_t fadd = (0x00u << 25) | op_fp;
    constexpr uint32_t fsub = (0x04u << 25) | op_fp;
    constexpr uint32_t fmul = (0x08u << 25) | op_fp;
    constexpr uint32_t fdiv = (0x0cu << 25) | op_fp;
    constexpr uint32_t fsqrt = (0x2cu << 25) | op_fp;
    constexpr uint32_t fmadd = 0x43u;
    constexpr uint32_t fmsub = 0x47u;
    constexpr uint32_t fnmsub = 0x4bu;
    constexpr uint32_t fnmadd = 0x4fu;
    constexpr unsigned vectors_per_operation = 20000;

    std::mt19937 generator(0x94114073u);
    uint64_t checks = 0;
    auto check = [&](const char *name, uint32_t instruction,
                     uint32_t a, uint32_t b, uint32_t c,
                     float expected) {
        uint32_t got = execute(dut, instruction, a, b, c);
        uint32_t want = canonicalize_nan(expected);
        if (got != want) {
            std::cerr << name << " mismatch a=0x" << std::hex << a
                      << " b=0x" << b << " c=0x" << c
                      << " got=0x" << got << " want=0x" << want
                      << std::dec << "\n";
            std::exit(1);
        }
        ++checks;
    };

    for (unsigned index = 0; index < vectors_per_operation; ++index) {
        uint32_t a_bits = generator();
        uint32_t b_bits = generator();
        uint32_t c_bits = generator();
        volatile float a = bits_float(a_bits);
        volatile float b = bits_float(b_bits);
        volatile float c = bits_float(c_bits);
        check("FADD.S", fadd, a_bits, b_bits, c_bits, a + b);
        check("FSUB.S", fsub, a_bits, b_bits, c_bits, a - b);
        check("FMUL.S", fmul, a_bits, b_bits, c_bits, a * b);
        check("FDIV.S", fdiv, a_bits, b_bits, c_bits, a / b);
        check("FSQRT.S", fsqrt, a_bits, 0, 0, std::sqrt(a));
        check("FMADD.S", fmadd, a_bits, b_bits, c_bits,
              std::fma(a, b, c));
        check("FMSUB.S", fmsub, a_bits, b_bits, c_bits,
              std::fma(a, b, -c));
        check("FNMSUB.S", fnmsub, a_bits, b_bits, c_bits,
              std::fma(-a, b, c));
        check("FNMADD.S", fnmadd, a_bits, b_bits, c_bits,
              std::fma(-a, b, -c));
    }

    std::cout << "[RV32F RANDOM PASS] " << checks
              << " RNE differential result checks passed\n";
    dut.final();
    return 0;
}
