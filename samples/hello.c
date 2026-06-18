#include <stdio.h>

int add_numbers(int a, int b) {
    return a + b;
}

int multiply_numbers(int a, int b) {
    return a * b;
}

int main(void) {
    printf("sum=%d product=%d\n", add_numbers(2, 3), multiply_numbers(4, 5));
    return 0;
}
