clear all;
clc;
close all;

% inputs: 
% nInfoBits, nUniqueWordBits, nGaurdBits, upSampler, Lw, Ls
% 
% Parameters:
% nInfoBits = number of bits of information
% nUniqueWordBits = number of bits in unique word
% nGaurdBits = number of gaurd bits
% 
%Lw = Length of the window
%Ls = Length of the step
%
%
%
% burst = 
% burstSymbols
% QPSK modulation
% n=4
% Icomp, Qcomp
% modulatedSignal
% upSampler
% upSampledSignal
% dec


nInfoBits  = 1000;
nUniquewordBits = 96;
nGuardBits = 0;

infoBits = randi(0:1, 1, nInfoBits);
uniqueWord = kron([ones(1,12)], [0 1 0 1 0 1 1 0]);%randi(0:1, 1, nUniquewordBits);
guardBits = randi(0:1, nGuardBits);


%Burst builder
burst=[guardBits uniqueWord infoBits guardBits];
%burst= uniqueWord;

% Modulation
n = 4;      % n-PSK modulation
% PSK symbols in binary sequence
IcompSymbol = zeros(1,n);
QcompSymbol = zeros(1,n);
for j=1:n
    IcompSymbol(j) = cos((j-1)*2*pi/n);
    QcompSymbol(j) = 1i*sin((j-1)*2*pi/n);
    PSKsymbolsBinary(j) = cos((j-1)*2*pi/n)+1i*sin((j-1)*2*pi/n);
end

% symbols arranging according to gray mapping
binarySequence = 0:n-1;
[graySequence, x] =  bin2gray(binarySequence','psk',n);
gray2bin = containers.Map(graySequence, binarySequence);
for j=1:n
    PSKsymbolsGray(j) = PSKsymbolsBinary(graySequence(j)+1);
end

% PSKsymbolsGray =  pskmod(0:n-1,n);
% IcompSymbol = real(PSKsymbolsGray);
% QcompSymbol = 1i*imag(PSKsymbolsGray);

% Convert Burst bits into symbols
bitsPerSymbol = log(n)/log(2);
for j=1:length(burst)/bitsPerSymbol
    dec = 0;
    for k=0:bitsPerSymbol-1          %binary to decimal conversion
        dec = dec*2^(k)+burst((j-1)*bitsPerSymbol+k+1);
    end
    burstSymbols(j) = dec;
end

% perform nPSK modulation
for j = 1:length(burstSymbols)
    modulatedSignal(j) = PSKsymbolsGray(burstSymbols(j)+1);
end


% up sampling
upSampler = 16;
upSamplingMatrix = [1 zeros(1,upSampler-1)];
upSampledSignal = interpn(modulatedSignal,4);%kron(modulatedSignal, upSamplingMatrix);


% raised cosine filter and interpolation
[NUM DEN] = rcosine(1, 16, 'sqrt', 0.35);
interpolatedSignal = conv(NUM, upSampledSignal);
% resizing the interpolatedSignal. remove extra bits 
interpolatedSignal = interpolatedSignal(.5*(length(NUM)-1)+1:length(interpolatedSignal)-.5*(length(NUM)-1));
%interpolatedSignal = interpn(modulatedSignal,4);%modulatedSignal;%interpolatedSignal(.5*(length(NUM)-1)+1:length(interpolatedSignal)-.5*(length(NUM)-1));
s = interpolatedSignal;


%channel g_t 
g_t=rician_channel(length(s));
%g_t=test(length(s));
%noise
noise = randn(1,length(interpolatedSignal))+1i*randn(1,length(interpolatedSignal));

%receivedSignal = conv(g_t,interpolatedSignal);
receivedSignal = g_t.*interpolatedSignal+noise*5;
% resizing the receivedSignal. remove extra bits and adding noise
%receivedSignal = receivedSignal(.5*(length(g_t)-1)+1:length(receivedSignal)-.5*(length(g_t)-1));
receivedSignal = receivedSignal+noise;

y=receivedSignal;
% Down sampling by 16;
y=decimate(y,16);
%y=modulatedSignal;


uw=modulatedSignal(1,1:48);


% Demodulation consits of three parts
% Only for QPSK

% 1. Channel Estimation
Lw = 41;
Ls = 11;
receivedSymbols_hat=uw;

for h=1:(length(y)-Lw)/Ls
    
    k=0:7;
    phs=0;  %theta_uw=0;
    y4sum=0;
    for l=1:Lw
        phs = phs+phase(y((h-1)*Ls+l)/receivedSymbols_hat((h-1)*Ls+l));
        y4sum = y4sum+y((h-1)*Ls+l)^4;
    end
    phs=phs/Lw;
    theta_k = 1/4*atan2(imag(y4sum),real(y4sum))+k*pi/4;
   
    % arg min of phase
    theta_hat(h) = arg_min(phs,theta_k);


    % Channel Compensation
    for j= ((Lw+1)/2+(h-1)*Ls-(Ls-1)/2):(Lw+h*Ls)
        %if j>length(uw)
            receivedSymbols_hat(((Lw+1)/2+(h-1)*Ls-(Ls-1)/2):(Lw+h*Ls)) = y(((Lw+1)/2+(h-1)*Ls-(Ls-1)/2):(Lw+h*Ls))*(cos(theta_hat(h))-1i*sin(theta_hat(h)));
        %end
    end
    disp('check 1');
end


% Hard Slicer for symbol detection
for j=1:length(receivedSymbols_hat)%length(y)
    symbolPhase=phase(receivedSymbols_hat(j));
    if symbolPhase <= pi/4 && symbolPhase >= -pi/4
        b = [0 0];
    elseif symbolPhase <= 3*pi/4 && symbolPhase >= pi/4
        b = [0 1];
    elseif symbolPhase <= -3*pi/4 || symbolPhase >= 3*pi/4
        b = [1 1];
    elseif symbolPhase <= -pi/4 && symbolPhase >= -3*pi/4
        b = [1 0];
    else
        display("Error in Hard Slicer. check if statements correctly for angles appropriately");
    end
    bits((2*(j-1)+1):2*(j-1)+2) = b;
end


%corrects = bits(1:50*2)==burst(1:50*2);%length(receivedSymbols_hat)*2);
corrects = bits==burst(1:length(receivedSymbols_hat)*2);
c=sum(corrects)
w=length(corrects)-c
figure;
plot(1:length(theta_hat),theta_hat*180/pi)