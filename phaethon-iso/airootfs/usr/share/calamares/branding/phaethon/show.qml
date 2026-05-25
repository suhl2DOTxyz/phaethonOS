import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation
    
    Slide {
        Image {
            id: background
            source: "phaethon-logo.png"
            width: 200; height: 200
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        Text {
            anchors.horizontalCenter: background.horizontalCenter
            anchors.top: background.bottom
            anchors.topMargin: 20
            text: "Welcome to PhaethonOS"
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
            font.pixelSize: 22
            color: "#C8FF00"
        }
    }
    
    Slide {
        Text {
            anchors.centerIn: parent
            text: "Though greatly he failed, more greatly he dared."
            wrapMode: Text.WordWrap
            width: presentation.width
            horizontalAlignment: Text.Center
            font.pixelSize: 20
            font.italic: true
            color: "#D4AF37"
        }
    }
}
