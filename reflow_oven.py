import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys
import serial
from PIL import Image
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
import pygame
import pygame.mixer

xsize = 250

# State thresholds
PREHEAT_TEMP = 150  # Around 150 degrees for State 1
PEAK_TEMP = 160  # Around 120 degrees for State 2
REFLOW_TEMP = 220  # Above 220 degrees for State 3
ROOM_TEMP = 25      # Assuming room temperature is around 25 degrees for State 5

current_state = "State 0"
previous_temp = 25  # Assuming we start at room temperature
image_opened = False  # Flag to track if the image has been opened
email_sent = False

# Email setup
EMAIL_ADDRESS = ''
EMAIL_PASSWORD = ''
RECIPIENT_EMAIL = ''

# Configure the serial port
ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

if ser.isOpen():
    print("Serial port is open")
else:
    ser.open()

# Initialize Pygame Mixer
pygame.init()
pygame.mixer.init()
# Load a sound file (ensure you have a sound file at the specified path)
sounds = {
    "Soaking": pygame.mixer.Sound("soak.mp3"),
    "Preheating": pygame.mixer.Sound("preheat.mp3"),
    "Peak": pygame.mixer.Sound("peak.mp3"),
    "REFLOW": pygame.mixer.Sound("overflow.mp3"),
    "Cooling": pygame.mixer.Sound("cooldown.mp3"),
    "OFF": pygame.mixer.Sound("off.mp3")
}

# Email sending function
def send_email(subject, body):
    msg = MIMEMultipart()
    msg['From'] = EMAIL_ADDRESS
    msg['To'] = RECIPIENT_EMAIL
    msg['Subject'] = subject
    msg.attach(MIMEText(body, 'plain'))
    try:
        server = smtplib.SMTP('smtp.gmail.com', 587)
        server.starttls()
        server.login(EMAIL_ADDRESS, EMAIL_PASSWORD)
        server.sendmail(EMAIL_ADDRESS, RECIPIENT_EMAIL, msg.as_string())
        server.quit()
        print("Email sent successfully")
    except Exception as e:
        print(f"Failed to send email: {e}")

def data_gen():
    t = data_gen.t
    while True:
        t += 0.5
        val = int(ser.readline())
        yield t, val

data_gen.t = -1

def get_state(y, previous_state, previous_temp):
    if previous_state == "State 0" and y >= ROOM_TEMP+5:
        line.set_color('goldenrod')
        return "Soaking"
    elif previous_state == "Soaking" and y >= PREHEAT_TEMP:
        line.set_color('orange')
        return "Preheating"
    elif previous_state == "Preheating" and y > PEAK_TEMP:
        line.set_color('red')
        return "Peak"
    elif previous_state == "Peak" and y > REFLOW_TEMP:
        line.set_color('mediumvioletred')
        return "REFLOW"
    elif previous_state == "REFLOW" and y <= REFLOW_TEMP-5:
        line.set_color('darkslateblue')
        return "Cooling"
    elif previous_state == "Cooling" and y <= ROOM_TEMP+35:
        line.set_color('blue')
        return "OFF"
    return previous_state

def update_state_text(t, y, state):
    # Remove the previous state text
    for txt in ax.texts:
        txt.set_visible(False)
    # Add new state text
    ax.text(t, y, f"{state}", fontsize=12, color='black', verticalalignment='bottom')

def run(data):
    global current_state, previous_temp, image_opened, email_sent
    # update the data
    t, y = data
    if t > -1:
        xdata.append(t)
        ydata.append(y)
        if t > xsize:  # Scroll to the left.
            ax.set_xlim(t - xsize, t)
        line.set_data(xdata, ydata)
        
    new_state = get_state(y, current_state, previous_temp)
    if new_state != current_state:
        if new_state in sounds:
            sounds[new_state].play()

        if new_state == "OFF" and not email_sent:
            send_email(f"Reflow Oven Status: {new_state}", f"Good Morning Dr.Jesus,\n   Group B3's soldering / toast is complete <3 \n")
            email_sent = True
        if new_state == "OFF" and not image_opened:
            img = Image.open('thanks.webp')
            img.show()
            image_opened = True

    current_state = new_state
    previous_temp = y
    update_state_text(t, y, current_state)
    temp_val_text.set_text(f"Temperature: {y}°C / {y*9/5+32}°F")

    return line,

def on_close_figure(event):
    ser.close()  # Close serial port
    sys.exit(0)

fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line, = ax.plot([], [], lw=2)
ax.set_xlabel('Time (seconds)')
ax.set_ylabel('Temperature (Degree Celsius)')
ax.set_ylim(-10, 250)
ax.set_xlim(0, xsize)
ax.grid()
xdata, ydata = [], []

# Animation
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=30, repeat=False)
temp_val_text = fig.text(0.8, 0.9, "", ha='center')

plt.show()
