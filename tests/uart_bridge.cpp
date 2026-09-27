// Bit-level serial harness: Python uses the same client as physical hardware.
#include "Vfa_uart_top.h"
#include "verilated.h"
#include <iostream>
#include <sstream>
#include <iomanip>
#include <vector>
#include <string>
#ifndef UART_CPB
#define UART_CPB 8
#endif

struct Simulation {
    VerilatedContext context;
    Vfa_uart_top dut{&context};
    std::vector<unsigned char> received;
    int rx_phase=0, countdown=0, bit=0, value=0;
    bool previous=true;
    void tick() {
        dut.clk=0;dut.eval();context.timeInc(5);
        dut.clk=1;dut.eval();context.timeInc(5);
        bool line=dut.uart_tx_pin;
        if(rx_phase==0) {
            if(previous && !line) {rx_phase=1;countdown=UART_CPB+UART_CPB/2-1;bit=0;value=0;}
        } else if(countdown>0) --countdown;
        else if(rx_phase==1) {
            value|=(int(line)<<bit);countdown=UART_CPB-1;
            if(++bit==8) rx_phase=2;
        } else {
            if(!line) {std::cerr<<"FPGA TX invalid stop bit\n";std::exit(2);}
            received.push_back(value);rx_phase=0;
        }
        previous=line;
        if(context.gotFinish()) std::exit(3);
    }
    void cycles(int n) {for(int i=0;i<n;i++) tick();}
    void send(unsigned char b,bool bad_stop=false,int clocks=UART_CPB) {
        dut.uart_rx_pin=0;cycles(clocks);
        for(int i=0;i<8;i++) {dut.uart_rx_pin=(b>>i)&1;cycles(clocks);}
        dut.uart_rx_pin=bad_stop?0:1;cycles(clocks);
        dut.uart_rx_pin=1;
    }
    bool complete() {
        if(received.size()<6) return false;
        unsigned size=(unsigned(received[4])<<8)|received[5];
        return received.size()>=size+8;
    }
    Simulation() {
        dut.rst_n=0;dut.uart_rx_pin=1;cycles(8);dut.rst_n=1;cycles(8);
    }
};

int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Simulation sim;
    std::string line;
    while(std::getline(std::cin,line)) {
        std::istringstream input(line);
        char op;input>>op;
        if(op=='Q') break;
        if(op=='T') {int n;input>>n;sim.cycles(n);std::cout<<"OK\n"<<std::flush;continue;}
        int clocks=UART_CPB;
        if(op=='P') input>>clocks;
        std::string hex;input>>hex;
        sim.received.clear();
        for(size_t i=0;i+1<hex.size();i+=2) {
            auto b=static_cast<unsigned char>(std::stoul(hex.substr(i,2),nullptr,16));
            sim.send(b,op=='F' && i+2==hex.size(),clocks);
        }
        sim.dut.uart_rx_pin=1;
        for(int i=0;i<UART_CPB*5000 && !sim.complete();i++) sim.tick();
        // Let the final stop bit and command FSM finish before another request.
        sim.cycles(UART_CPB+8);
        if(sim.received.empty()) std::cout<<"-";
        else for(auto b:sim.received) std::cout<<std::hex<<std::setw(2)<<std::setfill('0')<<unsigned(b);
        std::cout<<std::dec<<"\n"<<std::flush;
    }
    sim.dut.final();
}
