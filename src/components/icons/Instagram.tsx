import React from 'react'

interface InstagramProps {

}

const Instagram: React.FC<InstagramProps> = () => {
        return (
          <svg
            viewBox="0 -0.5 25 25"
            fill="none"
            width={"50px"}
            height={"50px"}
          >
            <g id="SVGRepo_bgCarrier" strokeWidth="0"></g>
            <g
              id="SVGRepo_tracerCarrier"
              strokeLinecap="round"
              strokeLinejoin="round"
            ></g>
            <g id="SVGRepo_iconCarrier">
              <path
                fillRule="evenodd"
                clipRule="evenodd"
                d="M15.5 5H9.5C7.29086 5 5.5 6.79086 5.5 9V15C5.5 17.2091 7.29086 19 9.5 19H15.5C17.7091 19 19.5 17.2091 19.5 15V9C19.5 6.79086 17.7091 5 15.5 5Z"
                stroke="#000000"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              ></path>{" "}
              <path
                fillRule="evenodd"
                clipRule="evenodd"
                d="M12.5 15C10.8431 15 9.5 13.6569 9.5 12C9.5 10.3431 10.8431 9 12.5 9C14.1569 9 15.5 10.3431 15.5 12C15.5 12.7956 15.1839 13.5587 14.6213 14.1213C14.0587 14.6839 13.2956 15 12.5 15Z"
                stroke="#000000"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              ></path>{" "}
              <rect
                x="15.5"
                y="9"
                width="2"
                height="2"
                rx="1"
                transform="rotate(-90 15.5 9)"
                fill="#000000"
              ></rect>{" "}
              <rect
                x="16"
                y="8.5"
                width="1"
                height="1"
                rx="0.5"
                transform="rotate(-90 16 8.5)"
                stroke="#000000"
                strokeLinecap="round"
              ></rect>{" "}
            </g>
          </svg>
        );
}

export default Instagram;