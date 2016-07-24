%% Part 1
clear all
clf

a = 1;
b = [0.25 0.25 0.25 0.25];
n = 1024;
fs = 15874;

% measured samples
fm = [0 300 600 900 1200 1500 1800 2100 2400 2700 3000 3300 3600 3969 4200 4500 4800 5100 5400 5700 6000 6300 6600 6900 7200 7500 7800 7929];
gain = [1 .9911 .9646 .9212 .864 .7916 .7098 .6164 .5164 .4124 .3101 .2071 .1087 0 .0619 .132 .1877 .2315 .2585 .2711 .2694 .2537 .2253 .186 .1391 .0845 .026 0];


[h,f] = freqz(b,a,n,fs);
hold on
plot(f,abs(h));
plot(fm,gain, 'or');
hold off
xlabel('Frequency (Hz)');
ylabel('Gain (V/V)');
title('FIR Filter Frequency Response')
legend('Simulated', 'Measured')

%% Part 2
clear all
clf

% Prepare subplots
figure(1);
for k = 1:2
    h(k) = subplot(2,1,k);
end

% Variables
t = linspace(0, 2*pi, 1000);
x = linspace(0, 2*pi, 100);

% Animation Loop
for n = 0:0.1:49.5; % Frequency Sweep
    [L, length] = size(x);
    source = 2.5*sin(n*x) + 2.5;
    sourceA = 2.5*sin(n*t) + 2.5;
    output = zeros(1,length);

    % Initial State
    init = [0 0 0];
    output(1) = (source(1) + init(1) + init(2) + init(3))/4;
    output(2) = (source(1) + source(2) + init(2) + init(3))/4;
    output(3) = (source(1) + source(2) + source(3) + init(3))/4;

    % FIR Filter
    for i = 4:length
        output(i) = (source(i) + source(i-1) + source(i-2) + source(i-3))/4;
    end

    % Plotting
    subplot(h(1));
    plot(t,sourceA,'r')
    axis([0 2*pi 0 5])
    title('Source Signal')
    refreshdata(h(1),'caller')

    subplot(h(2));
    %plot(t,sourceA,'r');
    stairs(x, output, 'g');
    axis([0 2*pi 0 5]);
    title('Filtered Signal')
    refreshdata(h(2),'caller')

    drawnow
end


